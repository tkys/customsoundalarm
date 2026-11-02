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
    let fade: PlaylistFadeSettings
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
        // 読み込む前にファイルの長さで10分上限を判定する。
        let readers = request.trackURLs.compactMap { TrackReader(url: $0) }
        guard !readers.isEmpty else { throw PlaylistRenderError.noTracks }

        let trackFrames = readers.map(\.totalOutputFrames)
        let durations = trackFrames.map {
            Double($0) / PlaylistRenderLogic.sampleRate
        }
        guard PlaylistRenderLogic.isWithinLimit(
            trackDurations: durations,
            fade: request.fade
        ) else {
            throw PlaylistRenderError.tooLong
        }

        let crossfadeFrames = request.fade.gapFade == .crossfade
            ? Int((PlaylistGapFade.crossfade.seconds * PlaylistRenderLogic.sampleRate).rounded())
            : 0
        let overlapFrames = (0..<max(0, trackFrames.count - 1)).reduce(0) { total, index in
            total + min(crossfadeFrames, min(trackFrames[index], trackFrames[index + 1]))
        }
        let totalOutputFrames = trackFrames.reduce(0, +) - overlapFrames

        let writer = try StreamingWriter(
            outputURL: request.outputURL,
            totalOutputFrames: totalOutputFrames,
            fade: request.fade,
            applyFadeIn: request.applyFadeIn
        )

        var pendingTail: [Float] = []

        for (index, reader) in readers.enumerated() {
            let frames = trackFrames[index]
            guard frames > 0 else { continue }

            if request.fade.gapFade == .crossfade {
                let overlap = index == 0
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

                // 次の曲のクロスフェード用に、この曲の末尾だけを保持する。
                // 最後の曲は次が無いので、末尾もそのまま書き出す。
                let isLast = index == readers.count - 1
                let tailFrames = isLast ? 0 : min(crossfadeFrames, frames)
                let restTailCount = max(0, tailFrames - head.count)
                var restTail: [Float] = []
                var readFromRest = 0
                while readFromRest < frames - head.count {
                    let remaining = frames - head.count - readFromRest
                    let chunk = reader.readFrames(min(4096, remaining))
                    if chunk.isEmpty { break }
                    readFromRest += chunk.count
                    restTail.append(contentsOf: chunk)
                    if restTail.count > restTailCount {
                        let writeCount = restTail.count - restTailCount
                        try writer.write(Array(restTail.prefix(writeCount)))
                        restTail.removeFirst(writeCount)
                    }
                }
                pendingTail = isLast ? [] : head + restTail
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
                        trackIndex: index,
                        trackCount: readers.count,
                        gapFade: request.fade.gapFade
                    )
                    try writer.write(samples)
                    trackWritten += chunk.count
                }
            }
        }

        if !pendingTail.isEmpty {
            try writer.write(pendingTail)
        }
        try writer.finish()

        return PlaylistRenderResult(
            fileName: request.outputURL.lastPathComponent,
            durationSeconds: Double(writer.writtenFrames) / PlaylistRenderLogic.sampleRate,
            trackCount: readers.count
        )
    }

    // MARK: - Gap fade

    private static func applyGapFade(
        _ samples: inout [Float],
        startIndex: Int,
        trackFrames: Int,
        trackIndex: Int,
        trackCount: Int,
        gapFade: PlaylistGapFade
    ) {
        guard gapFade != .off, !samples.isEmpty else { return }
        let fadeFrames = min(
            trackFrames,
            Int((gapFade.seconds * PlaylistRenderLogic.sampleRate).rounded())
        )
        guard fadeFrames > 0 else { return }

        for offset in samples.indices {
            let trackSample = startIndex + offset
            if trackIndex > 0, trackSample < fadeFrames {
                samples[offset] *= PlaylistRenderLogic.fadeInGain(
                    index: trackSample,
                    fadeSeconds: gapFade.seconds
                )
            }
            if trackIndex < trackCount - 1,
               trackSample >= trackFrames - fadeFrames {
                samples[offset] *= PlaylistRenderLogic.fadeOutGain(
                    indexFromEnd: trackFrames - 1 - trackSample,
                    fadeSeconds: gapFade.seconds
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
        fade: PlaylistFadeSettings,
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
        self.applyFadeIn = applyFadeIn && fade.fadeIn != .off
        self.fadeInSeconds = fade.fadeIn.seconds
        self.fadeInFrames = applyFadeIn
            ? min(
                totalOutputFrames,
                Int((fade.fadeIn.seconds * PlaylistRenderLogic.sampleRate).rounded())
            )
            : 0
        self.endFadeFrames = fade.endFade
            ? min(
                totalOutputFrames,
                Int((0.5 * PlaylistRenderLogic.sampleRate).rounded())
            )
            : 0
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
