import Foundation
@preconcurrency import AVFoundation

/// プレイリスト書き出しの失敗理由（#151）。
enum PlaylistRenderError: String, Error, Equatable, Sendable {
    case noTracks = "no_tracks"
    case unreadableSource = "unreadable_source"
    case renderFailed = "render_failed"
    case writeFailed = "write_failed"
    case tooLong = "too_long"
}

/// プレイリスト書き出しの入力。
struct PlaylistRenderRequest: Sendable {
    let trackURLs: [URL]
    /// アラームの「やさしく鳴り始める」
    let fadeIn: PlaylistFadeIn
    /// プレイリストの曲のつなぎ方
    let transition: PlaylistTransition
    /// バックアップ用は false（最初から大きく鳴らす）
    let applyFadeIn: Bool
    let outputURL: URL
}

struct PlaylistRenderResult: Sendable, Equatable {
    let fileName: String
    let durationSeconds: Double
    let trackCount: Int
}

/// 複数の音を1本の CAF に連結し、フェードを適用する（#151）。
///
/// メモリを抑えるため、1曲ずつチャンク単位で読み込み・書き出しする。
/// クロスフェードで保持するのは前の曲の末尾（最大2秒）だけ。
/// 出力は PCM16 / 44.1kHz / mono。再正規化・増幅はしない。
enum PlaylistRenderer {

    static func generate(_ request: PlaylistRenderRequest) throws -> PlaylistRenderResult {
        // 1周分のリーダーで長さを測り、10分上限は1周の長さで判定する（#181）。
        let basePairs = request.trackURLs.compactMap { url -> (URL, TrackReader)? in
            guard let reader = TrackReader(url: url) else { return nil }
            return (url, reader)
        }
        guard !basePairs.isEmpty else { throw PlaylistRenderError.noTracks }

        var baseReaders = basePairs.map(\.1)
        let baseURLs = basePairs.map(\.0)
        let baseFrames = baseReaders.map(\.totalOutputFrames)
        let baseDurations = baseFrames.map {
            Double($0) / PlaylistRenderLogic.sampleRate
        }
        guard PlaylistRenderLogic.isWithinLimit(
            trackDurations: baseDurations,
            transition: request.transition
        ) else {
            throw PlaylistRenderError.tooLong
        }

        // やさしく鳴り始めるが短い音源で終わらないよう、実際の書き出し長に
        // 基づいて周回数を決める（#181）。
        let crossfadeFrames = request.transition == .crossfade
            ? Int((PlaylistTransition.crossfade.seconds * PlaylistRenderLogic.sampleRate).rounded())
            : 0
        let cycles = PlaylistRenderLogic.fadeInCycleCount(
            baseTrackFrames: baseFrames,
            crossfadeFrames: crossfadeFrames,
            fadeIn: request.fadeIn,
            applyFadeIn: request.applyFadeIn
        )

        let sourceTrackCount = baseReaders.count
        let trackFrames = Array(repeating: baseFrames, count: cycles).flatMap { $0 }

        // 1周目は計測に使ったリーダーをそのまま使い、2周目以降は1周ずつ
        // 新しいリーダーを作る（AVAudioConverter の状態を持ち越さず、
        // 短い音源で周回数が多くてもファイルを開きっぱなしにしない）。
        var firstCycleReaders: [TrackReader]? = baseReaders
        baseReaders.removeAll()

        // 実際のストリーミングと同じ重なり方で、書き出されるフレーム数を
        // 予測する（エンドフェードの基準を実際の長さに合わせる）。
        let totalOutputFrames = PlaylistRenderLogic.renderedFrameCount(
            trackFrames: trackFrames,
            crossfadeFrames: crossfadeFrames
        )

        let writer = try StreamingWriter(
            outputURL: request.outputURL,
            totalOutputFrames: totalOutputFrames,
            fadeIn: request.fadeIn,
            applyFadeIn: request.applyFadeIn
        )

        var pendingTail: [Float] = []
        let totalTrackCount = trackFrames.count
        var globalIndex = 0

        for _ in 0..<cycles {
            let cycleReaders: [TrackReader]
            if let first = firstCycleReaders {
                cycleReaders = first
                firstCycleReaders = nil
            } else {
                cycleReaders = baseURLs.compactMap { TrackReader(url: $0) }
                guard cycleReaders.count == baseURLs.count else {
                    throw PlaylistRenderError.unreadableSource
                }
            }

            for (index, reader) in cycleReaders.enumerated() {
                let frames = baseFrames[index]
                guard frames > 0 else {
                    globalIndex += 1
                    continue
                }

                if request.transition == .crossfade {
                    let overlap = globalIndex == 0
                        ? 0
                        : min(crossfadeFrames, pendingTail.count, frames)
                    var head: [Float] = []
                    if overlap > 0 {
                        head = reader.readFrames(overlap)
                        let previous = pendingTail.suffix(overlap)
                        var mixed = [Float](repeating: 0, count: overlap)
                        let previousStart = previous.startIndex
                        for sampleIndex in 0..<overlap {
                            let mix = Float(sampleIndex) / Float(overlap)
                            mixed[sampleIndex] = PlaylistRenderLogic.crossfadeMix(
                                a: previous[previousStart + sampleIndex],
                                b: head[sampleIndex],
                                mix: mix
                            )
                        }
                        try writer.write(mixed)
                    }

                    // 先頭をミックスした残りの部分から、末尾だけを次の曲のために保持する。
                    // 先頭（head）はすでに書き出し済みなので pendingTail に含めない。
                    let isLast = globalIndex == totalTrackCount - 1
                    let tailFrames = isLast
                        ? 0
                        : min(crossfadeFrames, max(0, frames - head.count))
                    var restTail: [Float] = []
                    var readFromRest = 0
                    while readFromRest < frames - head.count {
                        let remaining = frames - head.count - readFromRest
                        let chunk = reader.readFrames(min(4096, remaining))
                        if chunk.isEmpty { break }
                        readFromRest += chunk.count
                        restTail.append(contentsOf: chunk)
                        if restTail.count > tailFrames {
                            let writeCount = restTail.count - tailFrames
                            try writer.write(Array(restTail.prefix(writeCount)))
                            restTail.removeFirst(writeCount)
                        }
                    }
                    pendingTail = isLast ? [] : restTail
                } else {
                    var trackWritten = 0
                    while trackWritten < frames {
                        let chunk = reader.readFrames(min(4096, frames - trackWritten))
                        if chunk.isEmpty { break }
                        var samples = chunk
                        applyGapFade(
                            &samples,
                            startIndex: trackWritten,
                            trackFrames: frames,
                            trackIndex: globalIndex,
                            trackCount: totalTrackCount,
                            transition: request.transition
                        )
                        try writer.write(samples)
                        trackWritten += chunk.count
                    }
                }

                globalIndex += 1
            }
        }

        if !pendingTail.isEmpty {
            try writer.write(pendingTail)
        }
        try writer.finish()

        return PlaylistRenderResult(
            fileName: request.outputURL.lastPathComponent,
            durationSeconds: Double(writer.writtenFrames) / PlaylistRenderLogic.sampleRate,
            trackCount: sourceTrackCount
        )
    }

    // MARK: - Gap fade

    private static func applyGapFade(
        _ samples: inout [Float],
        startIndex: Int,
        trackFrames: Int,
        trackIndex: Int,
        trackCount: Int,
        transition: PlaylistTransition
    ) {
        guard transition != .off, !samples.isEmpty else { return }
        let fadeFrames = min(
            trackFrames,
            Int((transition.seconds * PlaylistRenderLogic.sampleRate).rounded())
        )
        guard fadeFrames > 0 else { return }

        for offset in samples.indices {
            let trackSample = startIndex + offset
            if trackIndex > 0, trackSample < fadeFrames {
                samples[offset] *= PlaylistRenderLogic.fadeInGain(
                    index: trackSample,
                    fadeSeconds: transition.seconds
                )
            }
            if trackIndex < trackCount - 1,
               trackSample >= trackFrames - fadeFrames {
                samples[offset] *= PlaylistRenderLogic.fadeOutGain(
                    indexFromEnd: trackFrames - 1 - trackSample,
                    fadeSeconds: transition.seconds
                )
            }
        }
    }
}

// MARK: - TrackReader

/// 1曲をチャンク単位で読み込み、44.1kHz / mono / float32 に変換する。
private final class TrackReader {
    private let file: AVAudioFile
    private let inputFormat: AVAudioFormat
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: PlaylistRenderLogic.sampleRate,
        channels: 1,
        interleaved: false
    )!
    private let converter: AVAudioConverter?
    private var pending: [Float] = []
    private let inputChunkFrames: AVAudioFrameCount

    let totalOutputFrames: Int

    init?(url: URL) {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        self.file = file
        self.inputFormat = file.processingFormat
        if inputFormat.sampleRate == PlaylistRenderLogic.sampleRate,
           inputFormat.channelCount == 1,
           inputFormat.commonFormat == .pcmFormatFloat32 {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                return nil
            }
            self.converter = converter
        }
        inputChunkFrames = AVAudioFrameCount(max(1, Int(inputFormat.sampleRate)))
        totalOutputFrames = Int(
            (Double(file.length) / inputFormat.sampleRate * PlaylistRenderLogic.sampleRate)
                .rounded()
        )
    }

    /// 最大 `count` フレームを返す。末尾では count より短くなる。
    func readFrames(_ count: Int) -> [Float] {
        guard count > 0 else { return [] }
        while pending.count < count {
            guard let chunk = readChunk(), !chunk.isEmpty else { break }
            pending.append(contentsOf: chunk)
        }
        let resultCount = min(count, pending.count)
        let result = Array(pending.prefix(resultCount))
        pending.removeFirst(resultCount)
        return result
    }

    private func readChunk() -> [Float]? {
        guard file.framePosition < file.length else { return nil }
        let remaining = file.length - file.framePosition
        let frames = AVAudioFrameCount(min(Int64(inputChunkFrames), remaining))
        guard frames > 0,
              let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: inputFormat,
                frameCapacity: frames
              ) else {
            return nil
        }
        do {
            try file.read(into: inputBuffer, frameCount: frames)
        } catch {
            return nil
        }
        guard inputBuffer.frameLength > 0 else { return nil }

        if converter == nil {
            guard let channel = inputBuffer.floatChannelData?[0] else { return nil }
            return Array(UnsafeBufferPointer(
                start: channel,
                count: Int(inputBuffer.frameLength)
            ))
        }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(
            Double(inputBuffer.frameLength) * ratio
        ) + 1024
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: capacity
        ) else {
            return nil
        }
        var conversionError: NSError?
        var supplied = false
        _ = converter?.convert(to: outputBuffer, error: &conversionError) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return inputBuffer
        }
        guard outputBuffer.frameLength > 0,
              let channel = outputBuffer.floatChannelData?[0] else {
            return nil
        }
        return Array(UnsafeBufferPointer(
            start: channel,
            count: Int(outputBuffer.frameLength)
        ))
    }
}

// MARK: - StreamingWriter

/// フェードを適用しながらチャンク単位で CAF に追記する。
private final class StreamingWriter {
    private let file: AVAudioFile
    private let format: AVAudioFormat
    private let totalFrames: Int
    private let fadeInFrames: Int
    private let endFadeFrames: Int
    private let fadeInSeconds: TimeInterval
    private let applyFadeIn: Bool
    private var buffer: [Float] = []

    private(set) var writtenFrames = 0

    init(
        outputURL: URL,
        totalOutputFrames: Int,
        fadeIn: PlaylistFadeIn,
        applyFadeIn: Bool
    ) throws {
        try? FileManager.default.removeItem(at: outputURL)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: PlaylistRenderLogic.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        guard let file = try? AVAudioFile(
            forWriting: outputURL,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        ) else {
            throw PlaylistRenderError.writeFailed
        }
        self.file = file
        self.format = file.processingFormat
        self.totalFrames = totalOutputFrames
        self.applyFadeIn = applyFadeIn && fadeIn != .off
        self.fadeInSeconds = fadeIn.seconds
        self.fadeInFrames = applyFadeIn
            ? min(
                totalOutputFrames,
                Int((fadeIn.seconds * PlaylistRenderLogic.sampleRate).rounded())
            )
            : 0
        // 終わりをフェードは常に 0.5 秒（#160）
        self.endFadeFrames = min(
            totalOutputFrames,
            Int((PlaylistRenderLogic.endFadeSeconds * PlaylistRenderLogic.sampleRate).rounded())
        )
        buffer.reserveCapacity(4096)
    }

    func write(_ samples: [Float]) throws {
        guard !samples.isEmpty else { return }
        for sample in samples {
            var value = sample
            if applyFadeIn, writtenFrames < fadeInFrames {
                value *= PlaylistRenderLogic.fadeInGain(
                    index: writtenFrames,
                    fadeSeconds: fadeInSeconds
                )
            }
            if endFadeFrames > 0 {
                let indexFromEnd = totalFrames - 1 - writtenFrames
                if indexFromEnd < endFadeFrames {
                    value *= PlaylistRenderLogic.fadeOutGain(
                        indexFromEnd: indexFromEnd,
                        fadeSeconds: 0.5
                    )
                }
            }
            buffer.append(value)
            writtenFrames += 1
            if buffer.count >= 4096 {
                try flush()
            }
        }
    }

    func finish() throws {
        try flush()
    }

    private func flush() throws {
        guard !buffer.isEmpty else { return }
        let frames = AVAudioFrameCount(buffer.count)
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frames
        ) else {
            buffer.removeAll(keepingCapacity: true)
            return
        }
        outputBuffer.frameLength = frames
        for index in buffer.indices {
            outputBuffer.floatChannelData![0][index] = buffer[index]
        }
        do {
            try file.write(from: outputBuffer)
        } catch {
            throw PlaylistRenderError.writeFailed
        }
        buffer.removeAll(keepingCapacity: true)
    }
}
