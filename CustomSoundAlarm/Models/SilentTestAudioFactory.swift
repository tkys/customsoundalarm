#if DEBUG
import Foundation
import AVFoundation

/// UI テスト用の音声ファイルをその場で作る（#256 レビュー）。
/// テスト用の CAF を製品に同梱しないため、DEBUG のシード処理からのみ使う。
enum SilentTestAudioFactory {

    /// 全体が無音の CAF（3秒・44.1kHz モノラル）。
    static func makeSilentFile(at url: URL, seconds: Double = 3) throws {
        try write(at: url, seconds: seconds, toneSeconds: 0)
    }

    /// 全体がごく小さい音の CAF。既存アラームの警告テスト用（計測は成功する）。
    static func makeQuietFile(at url: URL, seconds: Double = 3) throws {
        try write(at: url, seconds: seconds, toneSeconds: seconds, amplitude: 0.0008)
    }

    /// 先頭だけ音があり、残りが無音の CAF（一部だけ無音の確認用）。
    static func makePartialSilentFile(
        at url: URL,
        seconds: Double = 3,
        toneSeconds: Double = 0.5
    ) throws {
        try write(at: url, seconds: seconds, toneSeconds: toneSeconds)
    }

    private static func write(
        at url: URL,
        seconds: Double,
        toneSeconds: Double,
        amplitude: Double = 0.2
    ) throws {
        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let frameCount = AVAudioFrameCount(sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else {
            throw CocoaError(.fileWriteUnknown)
        }
        buffer.frameLength = frameCount

        let toneFrames = min(frameCount, AVAudioFrameCount(sampleRate * toneSeconds))
        let frequency = 440.0
        for frame in 0..<Int(frameCount) {
            if frame < Int(toneFrames) {
                let t = Double(frame) / sampleRate
                channel[frame] = Float(sin(2 * .pi * frequency * t) * amplitude)
            } else {
                channel[frame] = 0
            }
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
        )
        try file.write(from: buffer)
    }
}
#endif
