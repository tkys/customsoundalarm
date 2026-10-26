import Foundation
@preconcurrency import AVFoundation

/// ITU-R BS.1770-4 の積分ラウドネス（モノラル・44.1kHz）を測る（#134）。
///
/// - K 特性フィルタ（44.1kHz 係数）
/// - 400ms ブロック・75% 重なり
/// - 絶対ゲート −70 LUFS / 相対ゲート −10 LU
/// - 無音なら nil
enum LoudnessMeter {

    struct Measurement: Equatable, Sendable {
        let lufs: Double
        let peakDb: Double
    }

    static let blockDuration: Double = 0.4
    static let overlap: Double = 0.75
    static let absoluteGateLufs: Double = -70
    static let relativeGateLu: Double = 10

    /// 44.1kHz の K 特性（high shelf → high pass）
    private static let shelfB = [1.5308412300503478, -2.6509799951547297, 1.169079079921587]
    private static let shelfA = [1.0, -1.6636551132560204, 0.7125954280732254]
    private static let highPassB = [1.0, -2.0, 1.0]
    private static let highPassA = [1.0, -1.989169673629796, 0.9891990357870393]

    static func measure(fileURL: URL) -> Measurement? {
        guard let buffer = AudioSampleLoader.loadMono44k(fileURL: fileURL) else {
            return nil
        }
        return measure(buffer: buffer)
    }

    static func measure(buffer: AVAudioPCMBuffer) -> Measurement? {
        guard buffer.format.sampleRate == AudioSampleLoader.sampleRate,
              buffer.format.channelCount == 1,
              let channel = buffer.floatChannelData?[0]
        else { return nil }

        let count = Int(buffer.frameLength)
        guard count > 0 else { return nil }

        var samples = [Double](repeating: 0, count: count)
        var peak: Double = 0
        for index in 0..<count {
            let value = Double(channel[index])
            samples[index] = value
            peak = max(peak, abs(value))
        }
        guard peak > 0 else { return nil }

        let shelf = biquad(samples, b: shelfB, a: shelfA)
        let filtered = biquad(shelf, b: highPassB, a: highPassA)

        let blockSize = Int(AudioSampleLoader.sampleRate * blockDuration)
        let hop = Int(Double(blockSize) * (1 - overlap))
        guard blockSize > 0, hop > 0, count >= blockSize else { return nil }

        var blockLoudness: [Double] = []
        var blockMeanSquares: [Double] = []
        var start = 0
        while start + blockSize <= count {
            var sumSquares = 0.0
            for index in start..<(start + blockSize) {
                sumSquares += filtered[index] * filtered[index]
            }
            let meanSquare = sumSquares / Double(blockSize)
            if meanSquare > 0 {
                let loudness = -0.691 + 10 * log10(meanSquare)
                if loudness > absoluteGateLufs {
                    blockLoudness.append(loudness)
                    blockMeanSquares.append(meanSquare)
                }
            }
            start += hop
        }

        guard !blockMeanSquares.isEmpty else { return nil }

        let absoluteMean = blockMeanSquares.reduce(0, +) / Double(blockMeanSquares.count)
        let absoluteLoudness = -0.691 + 10 * log10(absoluteMean)
        let relativeThreshold = absoluteLoudness - relativeGateLu

        var gatedSquares: [Double] = []
        for (index, loudness) in blockLoudness.enumerated() where loudness > relativeThreshold {
            gatedSquares.append(blockMeanSquares[index])
        }
        guard !gatedSquares.isEmpty else { return nil }

        let gatedMean = gatedSquares.reduce(0, +) / Double(gatedSquares.count)
        let integrated = -0.691 + 10 * log10(gatedMean)
        return Measurement(lufs: integrated, peakDb: 20 * log10(peak))
    }

    /// 計測値を分析用の区分にする（#134）
    static func bucket(forLufs lufs: Double?) -> String {
        guard let lufs else { return "silent" }
        if lufs >= -9 { return ">=-9" }
        if lufs > -14 { return "-9~-14" }
        if lufs > -20 { return "-14~-20" }
        if lufs > -30 { return "-20~-30" }
        return "<-30"
    }

    private static func biquad(_ input: [Double], b: [Double], a: [Double]) -> [Double] {
        var output = [Double](repeating: 0, count: input.count)
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for index in input.indices {
            let x = input[index]
            let y = b[0] * x + b[1] * x1 + b[2] * x2 - a[1] * y1 - a[2] * y2
            x2 = x1; x1 = x
            y2 = y1; y1 = y
            output[index] = y
        }
        return output
    }
}
