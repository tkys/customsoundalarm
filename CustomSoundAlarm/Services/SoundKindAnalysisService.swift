import AVFoundation
import Accelerate
import CoreMedia
import Foundation
import SoundAnalysis
import os

/// 取り込み時の既存の計測値（#202）。`custom_sound_imported` は保存直後に送り、
/// 判定後の `sound_analyzed` には source だけを引き継ぐ。
struct SoundImportAnalytics: Sendable, Equatable {
    let source: SoundImportSource
    let peakDbBucket: String?
    let gainDbBucket: String?
    let lufsBucket: String?
    let shareMedia: ShareImportMedia?
    let volumeNoticeShown: Bool
}

/// 取り込んだ音の種類を端末内で1本ずつ判定する（#202）。
/// メインスレッドを止めず、同時に複数は走らせない。
@Observable
@MainActor
final class SoundKindAnalysisService {
    static let shared = SoundKindAnalysisService()

    private let logger = Logger(
        subsystem: "com.tkysdev.customsoundalarm",
        category: "SoundKind"
    )

    private enum Origin {
        case imported
        case backfill
    }

    private struct Job {
        let soundID: UUID
        let origin: Origin
        /// 取り込みの判定なら、sound_analyzed に付ける source。
        let source: SoundImportSource?
    }

    private var queue: [Job] = []
    private var queuedIDs: Set<UUID> = []
    private var currentTask: Task<Void, Never>?

    private init() {}

    /// 取り込み直後に呼ぶ。`custom_sound_imported` は今までどおり保存直後に送り、
    /// 判定は待ち行列の先頭（既存の音より前）に積む。UI は待たせない。
    func analyzeNewImport(soundID: UUID, analytics: SoundImportAnalytics) {
        // 取り込みの記録は判定を待たせない（#202 レビュー）。
        AnalyticsService.shared.capture(.customSoundImported(
            source: analytics.source,
            peakDbBucket: analytics.peakDbBucket,
            gainDbBucket: analytics.gainDbBucket,
            lufsBucket: analytics.lufsBucket,
            shareMedia: analytics.shareMedia,
            volumeNoticeShown: analytics.volumeNoticeShown
        ))

        #if DEBUG
        // UIテストでは、判定を明示したとき以外は走らせない。
        guard !AppGroup.isUITestRun || AppGroup.isUITestSoundKindAnalysis else { return }
        #endif
        enqueue(Job(
            soundID: soundID,
            origin: .imported,
            source: analytics.source
        ), atFront: true)
    }

    /// 判定前に取り込まれた音を、前面にいる間に1本ずつ判定する。
    func enqueueBackfillIfNeeded() {
        #if DEBUG
        guard !AppGroup.isUITestRun || AppGroup.isUITestSoundKindAnalysis else { return }
        #endif
        for sound in SoundStore.shared.sounds
        where !sound.isPreset
            && (sound.analysisVersion ?? 0) < SoundKindAnalysisResult.currentVersion {
            enqueue(Job(
                soundID: sound.id,
                origin: .backfill,
                source: nil
            ))
        }
    }

    /// 鳴動が終わった・前面に戻ったときに、止まっていた続きを始める。
    func resumeIfNeeded() {
        startNextIfPossible()
    }

    private func enqueue(_ job: Job, atFront: Bool = false) {
        guard !queuedIDs.contains(job.soundID) else { return }
        queuedIDs.insert(job.soundID)
        if atFront {
            // 新しい取り込みは、すでに並んでいる取り込みの後・既存の音より前に入れる。
            let index = queue.firstIndex { $0.origin != .imported } ?? queue.endIndex
            queue.insert(job, at: index)
        } else {
            queue.append(job)
        }
        startNextIfPossible()
    }

    private func startNextIfPossible() {
        guard currentTask == nil, !queue.isEmpty else { return }
        // アラームが鳴っている間は始めない。終わったら resumeIfNeeded() で再開する。
        guard !AlarmScheduler.shared.isAlarmRinging else { return }
        let job = queue.removeFirst()
        currentTask = Task { [weak self] in
            await self?.run(job)
        }
    }

    private func run(_ job: Job) async {
        guard let sound = SoundStore.shared.sounds.first(where: { $0.id == job.soundID }) else {
            complete(job, result: .unknown, soundExists: false)
            return
        }
        let url = AudioConverter.shared.soundsDirectory
            .appendingPathComponent(sound.fileName)
        let result = await SoundKindClassifier.analyze(
            fileURL: url,
            checksSilence: job.origin == .backfill
        )
        complete(job, result: result, soundExists: true)
    }

    private func complete(
        _ job: Job,
        result: SoundKindAnalysisResult,
        soundExists: Bool
    ) {
        if soundExists {
            SoundStore.shared.updateAnalysis(
                soundID: job.soundID,
                contentKind: result.contentKind,
                bpm: result.bpm,
                vocalStartSeconds: result.vocalStartSeconds,
                analysisVersion: result.analysisVersion
            )
            AnalyticsService.shared.setUserProperties(
                AnalyticsUserProperties.soundKindProperties(sounds: SoundStore.shared.sounds)
            )
        }

        switch job.origin {
        case .imported:
            guard soundExists else { break }
            AnalyticsService.shared.capture(.soundAnalyzed(
                contentKind: result.contentKind,
                bpmBucket: AnalyticsBuckets.bpmBucket(bpm: result.bpm),
                trigger: .imported,
                source: job.source
            ))
        case .backfill:
            guard soundExists else { break }
            AnalyticsService.shared.capture(.soundAnalyzed(
                contentKind: result.contentKind,
                bpmBucket: AnalyticsBuckets.bpmBucket(bpm: result.bpm),
                trigger: .backfill
            ))
        }

        logger.info(
            "Sound kind analyzed: \(result.contentKind.rawValue, privacy: .public)"
        )
        queuedIDs.remove(job.soundID)
        currentTask = nil
        startNextIfPossible()
    }
}

/// SoundAnalysis（version1）の分類と、区分・BPM の決定。
enum SoundKindClassifier {
    /// 3秒の窓・50%の重なり。検証（sound-kind-lab）と同じ設定。
    static let windowSeconds = 3.0
    static let overlap = 0.5
    static let topLabels = 3

    static func analyze(
        fileURL: URL,
        checksSilence: Bool
    ) async -> SoundKindAnalysisResult {
        await Task.detached(priority: .utility) {
            if checksSilence, SoundKindSilence.isSilent(fileURL: fileURL) {
                return SoundKindAnalysisResult.unknown
            }
            let windows = classifyWindows(fileURL: fileURL)
            guard !windows.isEmpty else { return SoundKindAnalysisResult.unknown }
            let decision = SoundKindDecision.decide(windows: windows)
            let bpm: Int?
            if decision.contentKind == .singing || decision.contentKind == .instrumental {
                bpm = BPMEstimator.estimate(fileURL: fileURL)
            } else {
                bpm = nil
            }
            return SoundKindAnalysisResult(
                contentKind: decision.contentKind,
                bpm: bpm,
                vocalStartSeconds: decision.contentKind == .singing
                    ? decision.vocalStartSeconds
                    : nil,
                analysisVersion: SoundKindAnalysisResult.currentVersion
            )
        }.value
    }

    private static func classifyWindows(fileURL: URL) -> [SoundKindWindow] {
        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            request.windowDuration = CMTime(
                seconds: windowSeconds,
                preferredTimescale: 48_000
            )
            request.overlapFactor = overlap
            let analyzer = try SNAudioFileAnalyzer(url: fileURL)
            let collector = WindowCollector(topN: topLabels)
            try analyzer.add(request, withObserver: collector)
            analyzer.analyze()
            return collector.windows
        } catch {
            return []
        }
    }
}

private final class WindowCollector: NSObject, SNResultsObserving {
    let topN: Int
    var windows: [SoundKindWindow] = []

    init(topN: Int) {
        self.topN = topN
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let top = result.classifications.prefix(topN).map {
            SoundKindLabelConfidence(
                label: $0.identifier,
                confidence: Double($0.confidence)
            )
        }
        windows.append(SoundKindWindow(
            startSeconds: result.timeRange.start.seconds,
            top: Array(top)
        ))
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {}

    func requestDidComplete(_ request: SNRequest) {}
}

/// 完全な無音は分類器にかけない（#202）。分類器は無音を music と出すため。
enum SoundKindSilence {
    static func isSilent(fileURL: URL) -> Bool {
        guard let file = try? AVAudioFile(
            forReading: fileURL,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        ) else { return false }
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: 44_100
        ) else { return false }

        var maxMagnitude: Float = 0
        while file.framePosition < file.length {
            let remaining = AVAudioFrameCount(min(
                Double(file.length - file.framePosition),
                Double(buffer.frameCapacity)
            ))
            guard remaining > 0 else { break }
            do {
                try file.read(into: buffer, frameCount: remaining)
            } catch {
                return false
            }
            guard buffer.frameLength > 0 else { break }
            if let channels = buffer.floatChannelData {
                for channel in 0..<Int(buffer.format.channelCount) {
                    var magnitude: Float = 0
                    vDSP_maxmgv(
                        channels[channel],
                        1,
                        &magnitude,
                        vDSP_Length(buffer.frameLength)
                    )
                    maxMagnitude = max(maxMagnitude, magnitude)
                }
            }
        }
        guard maxMagnitude > 0 else { return true }
        let peakDb = 20 * log10(Double(maxMagnitude))
        return peakDb < LoudnessNormalizer.silenceThresholdDb
    }
}
