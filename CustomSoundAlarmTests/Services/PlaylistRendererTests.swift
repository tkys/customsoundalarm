import Foundation
import Testing
@preconcurrency import AVFoundation
@testable import CustomSoundAlarm

struct PlaylistRendererTests {

    private let sampleRate = 44_100.0

    private func makeCAF(
        seconds: Double,
        value: Float = 0.5
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).caf")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let frames = Int(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(frames)
        )!
        buffer.frameLength = AVAudioFrameCount(frames)
        for index in 0..<frames {
            buffer.floatChannelData![0][index] = value
        }
        try file.write(from: buffer)
        return url
    }

    private func outputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).caf")
    }

    private func loadOutput(_ url: URL) -> [Float] {
        guard let buffer = AudioSampleLoader.loadMono44k(fileURL: url),
              let channel = buffer.floatChannelData?[0] else {
            return []
        }
        return Array(UnsafeBufferPointer(
            start: channel,
            count: Int(buffer.frameLength)
        ))
    }

    private func peak(_ samples: [Float]) -> Float {
        samples.reduce(0) { max($0, abs($1)) }
    }

    @Test
    func concatenatesTwoTracks() throws {
        let a = try makeCAF(seconds: 1)
        let b = try makeCAF(seconds: 1)
        let output = outputURL()
        defer {
            try? FileManager.default.removeItem(at: a)
            try? FileManager.default.removeItem(at: b)
            try? FileManager.default.removeItem(at: output)
        }

        let result = try PlaylistRenderer.generate(PlaylistRenderRequest(
            trackURLs: [a, b],
            fadeIn: .off,
            transition: .off,
            applyFadeIn: true,
            outputURL: output
        ))

        #expect(result.trackCount == 2)
        #expect(abs(result.durationSeconds - 2) < 0.05)
    }

    @Test
    func crossfadeShortensOutput() throws {
        let a = try makeCAF(seconds: 5)
        let b = try makeCAF(seconds: 5)
        let output = outputURL()
        defer {
            try? FileManager.default.removeItem(at: a)
            try? FileManager.default.removeItem(at: b)
            try? FileManager.default.removeItem(at: output)
        }

        let result = try PlaylistRenderer.generate(PlaylistRenderRequest(
            trackURLs: [a, b],
            fadeIn: .off,
            transition: .crossfade,
            applyFadeIn: true,
            outputURL: output
        ))

        #expect(abs(result.durationSeconds - 8) < 0.05)
    }

    @Test
    func fadeIn_makesTheStartQuieter() throws {
        let a = try makeCAF(seconds: 2)
        let output = outputURL()
        defer {
            try? FileManager.default.removeItem(at: a)
            try? FileManager.default.removeItem(at: output)
        }

        _ = try PlaylistRenderer.generate(PlaylistRenderRequest(
            trackURLs: [a],
            fadeIn: .five,
            transition: .off,
            applyFadeIn: true,
            outputURL: output
        ))

        let samples = loadOutput(output)
        let firstTenth = Array(samples.prefix(Int(0.1 * sampleRate)))
        let lastHalf = Array(samples.suffix(Int(0.5 * sampleRate)))
        #expect(peak(firstTenth) < peak(lastHalf))
    }

    private func assertCrossfadeRepeat(
        trackSeconds: [Double],
        minimumDuration: Double
    ) throws {
        let urls = try trackSeconds.map {
            try makeCAF(seconds: $0, value: 1.0)
        }
        let output = outputURL()
        defer {
            for url in urls {
                try? FileManager.default.removeItem(at: url)
            }
            try? FileManager.default.removeItem(at: output)
        }

        let result = try PlaylistRenderer.generate(PlaylistRenderRequest(
            trackURLs: urls,
            fadeIn: .thirty,
            transition: .crossfade,
            applyFadeIn: true,
            outputURL: output
        ))

        #expect(
            result.durationSeconds >= minimumDuration - 0.1,
            "expected >= \(minimumDuration)s, got \(result.durationSeconds)s"
        )
        #expect(
            peak(loadOutput(output)) > 0.99,
            "maximum volume was not reached for \(trackSeconds)"
        )

        // 実際のファイル長と、書き出しループと同じ計算の予測が一致すること。
        let trackFrames = trackSeconds.map {
            Int(($0 * sampleRate).rounded())
        }
        let crossfadeFrames = Int(
            (PlaylistTransition.crossfade.seconds * sampleRate).rounded()
        )
        let cycles = PlaylistRenderLogic.fadeInCycleCount(
            baseTrackFrames: trackFrames,
            crossfadeFrames: crossfadeFrames,
            fadeIn: .thirty,
            applyFadeIn: true
        )
        let repeated = Array(
            repeating: trackFrames,
            count: cycles
        ).flatMap { $0 }
        let predictedFrames = PlaylistRenderLogic.renderedFrameCount(
            trackFrames: repeated,
            crossfadeFrames: crossfadeFrames
        )
        let actualFrames = loadOutput(output).count
        #expect(
            actualFrames == predictedFrames,
            "actual \(actualFrames) frames != predicted \(predictedFrames)"
        )
    }

    @Test
    func crossfadePlaylistsReachFullVolume() throws {
        // 1周の実際の長さ L に対して、設定30秒 + L 以上の長さになること。
        try assertCrossfadeRepeat(
            trackSeconds: [3],
            minimumDuration: 33
        )
        try assertCrossfadeRepeat(
            trackSeconds: [3, 3],
            minimumDuration: 34
        )
        try assertCrossfadeRepeat(
            trackSeconds: [5, 5],
            minimumDuration: 38
        )
        try assertCrossfadeRepeat(
            trackSeconds: [1],
            minimumDuration: 31
        )
    }

    @Test
    func shortSourceWithFadeIn_repeatsAndReachesFullVolume() throws {
        let a = try makeCAF(seconds: 5, value: 1.0)
        let output = outputURL()
        defer {
            try? FileManager.default.removeItem(at: a)
            try? FileManager.default.removeItem(at: output)
        }

        // 5秒の音源 + 30秒フェード = ceil(30/5)+1 = 7周 = 35秒。
        let result = try PlaylistRenderer.generate(PlaylistRenderRequest(
            trackURLs: [a],
            fadeIn: .thirty,
            transition: .off,
            applyFadeIn: true,
            outputURL: output
        ))

        #expect(abs(result.durationSeconds - 35) < 0.1)

        let samples = loadOutput(output)
        #expect(peak(samples) > 0.99, "最大音量に届いていない")

        // 30秒時点でフェードインが完了し、末尾0.5秒のフェード前まで最大音量が続く。
        let afterFadeIn = Array(samples.dropFirst(Int(30 * sampleRate)))
        let beforeEndFade = Array(afterFadeIn.prefix(Int(4.5 * sampleRate)))
        #expect(peak(beforeEndFade) > 0.99)
    }

    @Test
    func backupRender_doesNotApplyFadeIn() throws {
        let a = try makeCAF(seconds: 2)
        let output = outputURL()
        defer {
            try? FileManager.default.removeItem(at: a)
            try? FileManager.default.removeItem(at: output)
        }

        let result = try PlaylistRenderer.generate(PlaylistRenderRequest(
            trackURLs: [a],
            fadeIn: .thirty,
            transition: .off,
            applyFadeIn: false,
            outputURL: output
        ))

        // 寝過ごし防止用は繰り返さない。
        #expect(abs(result.durationSeconds - 2) < 0.05)

        let samples = loadOutput(output)
        let firstTenth = Array(samples.prefix(Int(0.1 * sampleRate)))
        let lastHalf = Array(samples.suffix(Int(0.5 * sampleRate)))
        #expect(abs(peak(firstTenth) - peak(lastHalf)) < 0.01)
    }

    @Test
    func crossfade_peakDoesNotExceedSource() throws {
        let a = try makeCAF(seconds: 2, value: 1.0)
        let b = try makeCAF(seconds: 2, value: 1.0)
        let output = outputURL()
        defer {
            try? FileManager.default.removeItem(at: a)
            try? FileManager.default.removeItem(at: b)
            try? FileManager.default.removeItem(at: output)
        }

        _ = try PlaylistRenderer.generate(PlaylistRenderRequest(
            trackURLs: [a, b],
            fadeIn: .off,
            transition: .crossfade,
            applyFadeIn: true,
            outputURL: output
        ))

        #expect(peak(loadOutput(output)) <= 1.0 + 0.001)
    }

    @Test
    func endFade_endsNearZero() throws {
        let a = try makeCAF(seconds: 1)
        let output = outputURL()
        defer {
            try? FileManager.default.removeItem(at: a)
            try? FileManager.default.removeItem(at: output)
        }

        _ = try PlaylistRenderer.generate(PlaylistRenderRequest(
            trackURLs: [a],
            fadeIn: .off,
            transition: .off,
            applyFadeIn: true,
            outputURL: output
        ))

        let samples = loadOutput(output)
        #expect(abs(samples.last ?? 1) < 0.01)
    }

    @Test
    func unreadableTrack_isSkipped() throws {
        let a = try makeCAF(seconds: 1)
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).caf")
        let output = outputURL()
        defer {
            try? FileManager.default.removeItem(at: a)
            try? FileManager.default.removeItem(at: output)
        }

        let result = try PlaylistRenderer.generate(PlaylistRenderRequest(
            trackURLs: [missing, a],
            fadeIn: .off,
            transition: .off,
            applyFadeIn: true,
            outputURL: output
        ))

        #expect(result.trackCount == 1)
        #expect(abs(result.durationSeconds - 1) < 0.05)
    }

    @Test
    func doesNotAmplify() throws {
        let a = try makeCAF(seconds: 2, value: 0.25)
        let output = outputURL()
        defer {
            try? FileManager.default.removeItem(at: a)
            try? FileManager.default.removeItem(at: output)
        }

        _ = try PlaylistRenderer.generate(PlaylistRenderRequest(
            trackURLs: [a],
            fadeIn: .off,
            transition: .off,
            applyFadeIn: true,
            outputURL: output
        ))

        let samples = loadOutput(output)
        #expect(abs(peak(samples) - 0.25) < 0.01)
    }

    @Test
    func noTracks_throws() {
        let output = outputURL()
        defer { try? FileManager.default.removeItem(at: output) }

        #expect(throws: PlaylistRenderError.noTracks) {
            _ = try PlaylistRenderer.generate(PlaylistRenderRequest(
                trackURLs: [],
                fadeIn: .off,
            transition: .off,
                applyFadeIn: true,
                outputURL: output
            ))
        }
    }

    @Test
    func threeTrackCrossfade_usesEachTracksTail() throws {
        let a = try makeCAF(seconds: 5, value: 0.1)
        let b = try makeCAF(seconds: 5, value: 0.2)
        let c = try makeCAF(seconds: 5, value: 0.3)
        let output = outputURL()
        defer {
            try? FileManager.default.removeItem(at: a)
            try? FileManager.default.removeItem(at: b)
            try? FileManager.default.removeItem(at: c)
            try? FileManager.default.removeItem(at: output)
        }

        let result = try PlaylistRenderer.generate(PlaylistRenderRequest(
            trackURLs: [a, b, c],
            fadeIn: .off,
            transition: .crossfade,
            applyFadeIn: true,
            outputURL: output
        ))

        // A(5) + B(5) + C(5) - 2s - 2s = 11s
        #expect(abs(result.durationSeconds - 11) < 0.05)
        let samples = loadOutput(output)
        #expect(samples.count > Int(10.5 * sampleRate))

        func value(at seconds: Double) -> Float {
            let index = min(samples.count - 1, Int(seconds * sampleRate))
            return samples[index]
        }

        // A/B crossfade: 3-5s
        #expect(abs(value(at: 4.0) - 0.15) < 0.02)
        // B only: 5-6s
        #expect(abs(value(at: 5.5) - 0.2) < 0.01)
        // B/C crossfade: 6-8s. 先頭（Bの最初の2秒）ではなく末尾が使われること。
        #expect(abs(value(at: 6.0) - 0.2) < 0.02)
        #expect(abs(value(at: 7.0) - 0.25) < 0.02)
        #expect(abs(value(at: 8.0) - 0.3) < 0.02)
        // C only
        #expect(abs(value(at: 9.5) - 0.3) < 0.01)
    }
}
