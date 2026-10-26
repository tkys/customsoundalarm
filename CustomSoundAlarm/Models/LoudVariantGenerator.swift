import Foundation
@preconcurrency import AVFoundation

/// ユーザーの音を「大きくした版」に変換する（#119 / #134）。
///
/// - 入力は先頭60秒まで
/// - 自前の先読みリミッタ（上限 −1 dBFS・先読み 5ms・リリース 80ms）を使う
/// - 目標は「元の音 +6 LU 以上・音をつぶさない範囲でできるだけ大きく・上限 −8 LUFS」
/// - 出力は PCM16 / 44.1kHz / mono CAF
/// - 元の音源は一切書き換えない
enum LoudVariantGenerator {

    /// 生成方式の版。古い版の `.loud.caf` は作り直す（#134）
    static let version: Int = 3

    /// ラウドネスの上限
    static let targetLufs: Double = -8

    /// 元の音からの最低改善量
    static let minimumGainLu: Double = 6

    /// ゲイン上限
    static let maxGainDb: Double = 30

    /// 出力の最大長
    static let maxDuration: TimeInterval = 60

    /// 平均ゲイン低減の上限（これを超えたら音質優先で止める）
    static let maxAverageReductionDb: Double = 1.5

    /// ゲインの探索刻み
    static let gainStepDb: Double = 1.5

    enum Source: String, Sendable, Equatable {
        case imported
        case preset
    }

    enum GenerateError: String, Error, Equatable {
        case unreadableSource = "unreadable_source"
        case silentSource = "silent_source"
        case renderFailed = "render_failed"
        case writeFailed = "write_failed"
        case sourceMissing = "source_missing"
    }

    /// ゲイン探索の1段（純ロジックのテスト用・#134）
    struct GainCandidate: Equatable, Sendable {
        let gain: Double
        let lufs: Double
        let averageReductionDb: Double
    }

    /// 探索した段から最終ゲインを選ぶ（純ロジック・#134）。
    /// - 平均低減 ≤ 1.5 dB かつ −8 LUFS 未満の最後の段を基本とする
    /// - それが「元の音 +6 LU」に届いていなければ、+6 に届く最初の段を採る（低減上限を超えてよい）
    /// - 元の音 +6 が −8 より上になる場合は、−8 未満の最後の段（上限優先）
    static func selectCandidate(
        _ candidates: [GainCandidate],
        sourceLufs: Double
    ) -> GainCandidate? {
        guard !candidates.isEmpty else { return nil }
        let floorLufs = sourceLufs + minimumGainLu
        let withinReduction = candidates.filter {
            $0.averageReductionDb <= maxAverageReductionDb && $0.lufs < targetLufs
        }

        if let best = withinReduction.last,
           best.lufs >= floorLufs || floorLufs > targetLufs {
            return best
        }
        if let floorCandidate = candidates.first(where: { $0.lufs >= floorLufs }) {
            return floorCandidate
        }
        return withinReduction.last ?? candidates[0]
    }

    struct Result: Equatable, Sendable {
        let fileName: String
        let gainDb: Double
        let durationSeconds: Double
        let source: Source
        /// 元の音（先頭60秒）の LUFS
        let sourceLufs: Double
        /// 出力の LUFS
        let outputLufs: Double
        /// リミッタのゲイン係数の時間平均（dB）
        let averageReductionDb: Double
        /// 探索した段数
        let attempts: Int
    }

    /// `<元の名前>.loud.caf`
    static func outputFileName(for sourceFileName: String) -> String {
        let base = sourceFileName.replacingOccurrences(of: ".caf", with: "")
        return "\(base).loud.caf"
    }

    static func generate(
        sourceURL: URL,
        outputURL: URL,
        sourceFileName: String,
        source: Source
    ) throws -> Result {
        guard let buffer = AudioSampleLoader.loadMono44k(
            fileURL: sourceURL,
            maxSeconds: maxDuration
        ), let channel = buffer.floatChannelData?[0] else {
            throw GenerateError.unreadableSource
        }

        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        guard let sourceMeasurement = LoudnessMeter.measure(samples: samples) else {
            throw GenerateError.silentSource
        }

        let sourcePeak = samples.reduce(Float(0)) { max($0, abs($1)) }
        guard sourcePeak > 0 else { throw GenerateError.silentSource }
        let sourcePeakDb = 20 * log10(Double(sourcePeak))

        // ピークを −1 dBFS にそろえるゲインと、LUFS 上限にそろえるゲインの小さい方から始める。
        // 実音源（クレストが大きい）ではピーク基準が大幅に低く、そこから +1.5 dB ずつ上げる。
        let peakNormalizationGain = -1 - sourcePeakDb
        let lufsGain = targetLufs - sourceMeasurement.lufs
        let startGain = min(maxGainDb, min(peakNormalizationGain, lufsGain))

        struct Candidate {
            let gain: Double
            let limiter: LookaheadLimiter.Result
            let lufs: Double
        }

        func evaluate(_ gain: Double) -> Candidate? {
            let limiter = LookaheadLimiter.process(samples: samples, gainDb: gain)
            guard let measurement = LoudnessMeter.measure(samples: limiter.samples) else {
                return nil
            }
            return Candidate(gain: gain, limiter: limiter, lufs: measurement.lufs)
        }

        var candidates: [Candidate] = []
        var gain = startGain
        while true {
            guard let candidate = evaluate(gain) else {
                throw GenerateError.renderFailed
            }
            candidates.append(candidate)

            if gain >= maxGainDb { break }
            if candidate.lufs >= targetLufs { break }
            if candidate.limiter.averageReductionDb > maxAverageReductionDb,
               candidate.lufs >= sourceMeasurement.lufs + minimumGainLu {
                break
            }
            // 低減上限を超えても、+6 LU に届くまでは上げ続ける
            let next = min(maxGainDb, gain + gainStepDb)
            if next <= gain { break }
            gain = next
        }

        guard !candidates.isEmpty else { throw GenerateError.renderFailed }

        let gainCandidates = candidates.map {
            GainCandidate(
                gain: $0.gain,
                lufs: $0.lufs,
                averageReductionDb: $0.limiter.averageReductionDb
            )
        }
        guard let selectedGain = Self.selectCandidate(
            gainCandidates,
            sourceLufs: sourceMeasurement.lufs
        ), let selected = candidates.first(where: { $0.gain == selectedGain.gain }) else {
            throw GenerateError.renderFailed
        }

        try write(samples: selected.limiter.samples, to: outputURL)

        return Result(
            fileName: outputURL.lastPathComponent,
            gainDb: selected.gain,
            durationSeconds: Double(selected.limiter.samples.count) / AudioSampleLoader.sampleRate,
            source: source,
            sourceLufs: sourceMeasurement.lufs,
            outputLufs: selected.lufs,
            averageReductionDb: selected.limiter.averageReductionDb,
            attempts: candidates.count
        )
    }

    private static func write(samples: [Float], to outputURL: URL) throws {
        try? FileManager.default.removeItem(at: outputURL)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: AudioSampleLoader.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        guard let outputFile = try? AVAudioFile(
            forWriting: outputURL,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        ) else {
            throw GenerateError.writeFailed
        }
        let format = outputFile.processingFormat
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw GenerateError.writeFailed
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for index in samples.indices {
            buffer.floatChannelData![0][index] = samples[index]
        }
        do {
            try outputFile.write(from: buffer)
        } catch {
            throw GenerateError.writeFailed
        }
    }
}
