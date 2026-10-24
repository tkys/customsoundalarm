import Foundation
@preconcurrency import AVFoundation

/// サウンドの大きさ（RMS）を測る純ロジック（#109 C）。
///
/// - 0.25 秒の窓ごとに RMS を出し、無音（−50 dBFS 未満）の窓を除外して全体 RMS を求める。
/// - アラーム音量そのものは OS 設定（着信音と通知音）で決まるため、ここでは音源の大小だけを見る。
enum SoundLoudness {

    /// 測定窓の長さ（秒）
    static let windowDuration: TimeInterval = 0.25

    /// この値未満の窓は無音として除外する
    static let silenceWindowDb: Double = -50

    /// 表示用の区分
    enum Level: String, Equatable, Sendable {
        case quiet
        case normal
        case loud
    }

    /// 区分の閾値（RMS dBFS）。境界は normal 側に含める。
    static let quietThresholdDb: Double = -15
    static let loudThresholdDb: Double = -10

    /// RMS dBFS を 3 区分に分類する。
    static func level(forRmsDb db: Double) -> Level {
        if db < quietThresholdDb { return .quiet }
        if db <= loudThresholdDb { return .normal }
        return .loud
    }

    /// 測定結果
    struct Measurement: Equatable, Sendable {
        /// 無音区間を除いた RMS（dBFS）
        let rmsDb: Double
        /// ピーク（dBFS）
        let peakDb: Double
    }

    /// ファイルの RMS / ピークを測る。読めない・全編無音なら nil。
    static func measure(fileURL: URL) -> Measurement? {
        guard let file = try? AVAudioFile(forReading: fileURL) else { return nil }
        return measure(file: file)
    }

    /// 開かれたファイルから測る（テスト用に分離）。
    static func measure(file: AVAudioFile) -> Measurement? {
        let format = file.processingFormat
        let channelCount = Int(format.channelCount)
        guard channelCount > 0 else { return nil }

        let windowFrames = max(1, Int(format.sampleRate * windowDuration))
        let bufferSize: AVAudioFrameCount = 4096
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize) else {
            return nil
        }

        var windowSumSquares = 0.0
        var windowSampleCount = 0
        var includedSumSquares = 0.0
        var includedSampleCount = 0
        var peak: Double = 0

        func flushWindow() {
            guard windowSampleCount > 0 else { return }
            let windowRms = sqrt(windowSumSquares / Double(windowSampleCount))
            let windowDb = 20 * log10(max(windowRms, 1e-9))
            if windowDb >= silenceWindowDb {
                includedSumSquares += windowSumSquares
                includedSampleCount += windowSampleCount
            }
            windowSumSquares = 0
            windowSampleCount = 0
        }

        do {
            try file.read(into: buffer)
        } catch {
            return nil
        }

        while buffer.frameLength > 0 {
            let frames = Int(buffer.frameLength)

            if let channels = buffer.floatChannelData {
                for channel in 0..<channelCount {
                    let samples = channels[channel]
                    for index in 0..<frames {
                        let sample = Double(samples[index])
                        let magnitude = abs(sample)
                        if magnitude > peak { peak = magnitude }
                        windowSumSquares += sample * sample
                        windowSampleCount += 1
                        if windowSampleCount >= windowFrames { flushWindow() }
                    }
                }
            } else if let channels = buffer.int16ChannelData {
                for channel in 0..<channelCount {
                    let samples = channels[channel]
                    for index in 0..<frames {
                        let sample = Double(samples[index]) / 32768.0
                        let magnitude = abs(sample)
                        if magnitude > peak { peak = magnitude }
                        windowSumSquares += sample * sample
                        windowSampleCount += 1
                        if windowSampleCount >= windowFrames { flushWindow() }
                    }
                }
            } else {
                return nil
            }

            do {
                try file.read(into: buffer)
            } catch {
                break
            }
        }
        flushWindow()

        guard includedSampleCount > 0, peak > 0 else { return nil }

        let rms = sqrt(includedSumSquares / Double(includedSampleCount))
        return Measurement(
            rmsDb: 20 * log10(max(rms, 1e-9)),
            peakDb: 20 * log10(max(peak, 1e-9))
        )
    }
}
