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
/// `LoudVariantGenerator` と同じく PCM16 / 44.1kHz / mono で書き出す。
/// フェードは音量を下げる方向だけに使い、クロスフェードでピークが
/// 元のピークを超えた場合は全体を下げて音割れを防ぐ。
enum PlaylistRenderer {

    static func generate(_ request: PlaylistRenderRequest) throws -> PlaylistRenderResult {
        var loaded: [[Float]] = []
        for url in request.trackURLs {
            guard let buffer = AudioSampleLoader.loadMono44k(fileURL: url),
                  let channel = buffer.floatChannelData?[0] else {
                continue
            }
            let samples = Array(UnsafeBufferPointer(
                start: channel,
                count: Int(buffer.frameLength)
            ))
            if !samples.isEmpty {
                loaded.append(samples)
            }
        }
        guard !loaded.isEmpty else { throw PlaylistRenderError.noTracks }

        let durations = loaded.map { Double($0.count) / PlaylistRenderLogic.sampleRate }
        guard PlaylistRenderLogic.isWithinLimit(
            trackDurations: durations,
            fade: request.fade
        ) else {
            throw PlaylistRenderError.tooLong
        }

        let sourcePeak = loaded.reduce(Float(0)) { current, samples in
            samples.reduce(current) { max($0, abs($1)) }
        }

        let output: [Float]
        if request.fade.gapFade == .crossfade {
            output = crossfade(loaded, seconds: PlaylistGapFade.crossfade.seconds)
        } else {
            output = concatenate(loaded, gapFade: request.fade.gapFade)
        }
        guard !output.isEmpty else { throw PlaylistRenderError.renderFailed }

        var faded = output
        if request.applyFadeIn, request.fade.fadeIn != .off {
            let fadeSeconds = request.fade.fadeIn.seconds
            let fadeFrames = min(
                faded.count,
                Int((fadeSeconds * PlaylistRenderLogic.sampleRate).rounded())
            )
            if fadeFrames > 0 {
                for index in 0..<fadeFrames {
                    faded[index] *= PlaylistRenderLogic.fadeInGain(
                        index: index,
                        fadeSeconds: fadeSeconds
                    )
                }
            }
        }

        if request.fade.endFade {
            let fadeSeconds = 0.5
            let fadeFrames = min(
                faded.count,
                Int((fadeSeconds * PlaylistRenderLogic.sampleRate).rounded())
            )
            if fadeFrames > 0 {
                for offset in 0..<fadeFrames {
                    let index = faded.count - 1 - offset
                    faded[index] *= PlaylistRenderLogic.fadeOutGain(
                        indexFromEnd: offset,
                        fadeSeconds: fadeSeconds
                    )
                }
            }
        }

        let mixedPeak = faded.reduce(Float(0)) { max($0, abs($1)) }
        let scale = PlaylistRenderLogic.peakScale(
            sourcePeak: sourcePeak,
            mixedPeak: mixedPeak
        )
        if scale < 1 {
            for index in faded.indices {
                faded[index] *= scale
            }
        }

        try write(samples: faded, to: request.outputURL)
        return PlaylistRenderResult(
            fileName: request.outputURL.lastPathComponent,
            durationSeconds: Double(faded.count) / PlaylistRenderLogic.sampleRate,
            trackCount: loaded.count
        )
    }

    // MARK: - Concatenation

    private static func concatenate(
        _ tracks: [[Float]],
        gapFade: PlaylistGapFade
    ) -> [Float] {
        let fadeSeconds = gapFade == .off ? 0 : gapFade.seconds
        var output: [Float] = []
        output.reserveCapacity(tracks.reduce(0) { $0 + $1.count })

        for (trackIndex, track) in tracks.enumerated() {
            var samples = track
            let fadeFrames = min(
                samples.count,
                Int((fadeSeconds * PlaylistRenderLogic.sampleRate).rounded())
            )
            if fadeFrames > 0 {
                if trackIndex > 0 {
                    for index in 0..<fadeFrames {
                        samples[index] *= PlaylistRenderLogic.fadeInGain(
                            index: index,
                            fadeSeconds: fadeSeconds
                        )
                    }
                }
                if trackIndex < tracks.count - 1 {
                    for offset in 0..<fadeFrames {
                        let index = samples.count - 1 - offset
                        samples[index] *= PlaylistRenderLogic.fadeOutGain(
                            indexFromEnd: offset,
                            fadeSeconds: fadeSeconds
                        )
                    }
                }
            }
            output.append(contentsOf: samples)
        }
        return output
    }

    private static func crossfade(
        _ tracks: [[Float]],
        seconds: TimeInterval
    ) -> [Float] {
        guard let first = tracks.first else { return [] }
        var output = first
        var lastTrackLength = first.count
        let fadeFrames = Int((seconds * PlaylistRenderLogic.sampleRate).rounded())

        for track in tracks.dropFirst() {
            let overlap = min(fadeFrames, min(lastTrackLength, track.count))
            guard overlap > 0 else {
                output.append(contentsOf: track)
                lastTrackLength = track.count
                continue
            }

            let start = output.count - overlap
            for index in 0..<overlap {
                let mix = Float(index) / Float(overlap)
                output[start + index] = output[start + index] * (1 - mix)
                    + track[index] * mix
            }
            output.append(contentsOf: track[overlap...])
            lastTrackLength = track.count
        }
        return output
    }

    // MARK: - Write

    private static func write(samples: [Float], to outputURL: URL) throws {
        try? FileManager.default.removeItem(at: outputURL)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: PlaylistRenderLogic.sampleRate,
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
            throw PlaylistRenderError.writeFailed
        }
        let format = outputFile.processingFormat
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw PlaylistRenderError.writeFailed
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for index in samples.indices {
            buffer.floatChannelData![0][index] = samples[index]
        }
        do {
            try outputFile.write(from: buffer)
        } catch {
            throw PlaylistRenderError.writeFailed
        }
    }
}
