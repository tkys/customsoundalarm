import Testing
import Foundation
import AVFoundation
@testable import CustomSoundAlarm

/// 動画（音声トラック付きファイル）からの音声抽出（#150）。
/// `export(to:as:)` への置き換え後も従来どおり成功することの回帰。
struct VideoAudioExtractorTests {

    /// 440Hz サイン波の音声のみ .m4a をその場で生成する（動画と同じ音声トラック付きファイル）。
    @MainActor
    private static func makeAudioFile(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("csa-test-audio-\(UUID().uuidString).m4a")
        let sampleRate = 44100.0
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        let frameCount = AVAudioFrameCount(sampleRate * seconds)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        let channel = try #require(buffer.floatChannelData?[0])
        for i in 0..<Int(frameCount) {
            channel[i] = Float(sin(2.0 * .pi * 440.0 * Double(i) / sampleRate)) * 0.3
        }
        try file.write(from: buffer)
        return url
    }

    @MainActor
    @Test
    func extractAudio_trimsRequestedRange() async throws {
        let source = try Self.makeAudioFile(seconds: 3.0)
        defer { try? FileManager.default.removeItem(at: source) }

        let output = try await VideoAudioExtractor.shared.extractAudio(
            from: source,
            startTime: 1.0,
            endTime: 2.0
        )
        defer { try? FileManager.default.removeItem(at: output) }

        // export(to:as:) が完了ファイルを返す（旧 export()/status 経路の置き換え・#150）
        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect(output.pathExtension == "m4a")

        let asset = AVURLAsset(url: output)
        let seconds = CMTimeGetSeconds(try await asset.load(.duration))
        #expect(
            0.8...1.2 ~= seconds,
            "1秒トリムなら約1秒のはず（実際 \(seconds)s）"
        )
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        #expect(!audioTracks.isEmpty, "音声トラックが含まれる")
    }
}
