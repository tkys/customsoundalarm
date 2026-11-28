import Accelerate
import Foundation

/// 取り込んだ音の BPM の目安（#202）。外部ライブラリは使わず、Accelerate だけで出す。
/// 歌・歌の無い曲のときだけ使う。出せなければ nil。
enum BPMEstimator {
    static let minimumBPM: Double = 60
    static let maximumBPM: Double = 200

    /// 音声ファイルの先頭60秒から BPM を推定する。長い曲でもメモリを増やさない。
    static func estimate(fileURL: URL) -> Int? {
        guard let buffer = AudioSampleLoader.loadMono44k(
            fileURL: fileURL,
            maxSeconds: 60
        ), let channel = buffer.floatChannelData?[0] else { return nil }
        let samples = Array(UnsafeBufferPointer(
            start: channel,
            count: Int(buffer.frameLength)
        ))
        return estimate(samples: samples, sampleRate: buffer.format.sampleRate)
    }

    /// 波形から BPM を推定する。
    /// 短いフレームのエネルギー差（オンセット）を作り、拍の間隔で自己相関を取る。
    static func estimate(samples: [Float], sampleRate: Double) -> Int? {
        guard sampleRate > 0, samples.count > Int(sampleRate) else { return nil }

        let frameSize = 1024
        let hop = 512
        var energies: [Float] = []
        var start = 0
        while start + frameSize <= samples.count {
            var rms: Float = 0
            samples.withUnsafeBufferPointer { pointer in
                guard let base = pointer.baseAddress else { return }
                vDSP_rmsqv(
                    base.advanced(by: start),
                    1,
                    &rms,
                    vDSP_Length(frameSize)
                )
            }
            energies.append(rms)
            start += hop
        }
        guard energies.count >= 8 else { return nil }

        var onset = [Float](repeating: 0, count: energies.count)
        for index in 1..<energies.count {
            onset[index] = max(0, energies[index] - energies[index - 1])
        }
        var mean: Float = 0
        vDSP_meanv(onset, 1, &mean, vDSP_Length(onset.count))
        let centered = onset.map { $0 - mean }

        let framesPerSecond = sampleRate / Double(hop)
        let minLag = max(1, Int((60.0 / maximumBPM) * framesPerSecond))
        let maxLag = min(
            centered.count - 2,
            Int((60.0 / minimumBPM) * framesPerSecond)
        )
        guard maxLag > minLag else { return nil }

        var scores = [Float](repeating: 0, count: centered.count)
        var bestLag = minLag
        var bestScore: Float = -.infinity
        centered.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return }
            for lag in minLag...maxLag {
                let count = centered.count - lag
                guard count > 0 else { continue }
                var dot: Float = 0
                vDSP_dotpr(
                    base,
                    1,
                    base.advanced(by: lag),
                    1,
                    &dot,
                    vDSP_Length(count)
                )
                let score = dot / Float(count)
                scores[lag] = score
                if score > bestScore {
                    bestScore = score
                    bestLag = lag
                }
            }
        }
        guard bestScore > 0 else { return nil }

        // 2拍ぶんの間隔を拾ったときは、半分の間隔（速い方）が強ければそちらを採る。
        // 例：150 BPM の音は 75 BPM の間隔でも自己相関が高い。
        let halfCenter = Int((Double(bestLag) / 2).rounded())
        let halfCandidates = (halfCenter - 1...halfCenter + 1).filter {
            $0 >= minLag && $0 < bestLag
        }
        if let halfLag = halfCandidates.max(by: { scores[$0] < scores[$1] }),
           scores[halfLag] >= bestScore * 0.65 {
            bestLag = halfLag
        }

        // 山の前後から放物線で拍の間隔を細かくする。
        var refinedLag = Double(bestLag)
        if bestLag > minLag, bestLag < maxLag {
            let previous = Double(scores[bestLag - 1])
            let center = Double(scores[bestLag])
            let next = Double(scores[bestLag + 1])
            let denominator = previous - 2 * center + next
            if abs(denominator) > 0.000_001 {
                let offset = 0.5 * (previous - next) / denominator
                refinedLag += max(-0.5, min(0.5, offset))
            }
        }
        guard refinedLag > 0 else { return nil }

        var bpm = 60.0 * framesPerSecond / refinedLag
        while bpm < minimumBPM { bpm *= 2 }
        while bpm > maximumBPM { bpm /= 2 }
        guard bpm.isFinite else { return nil }
        return Int(bpm.rounded())
    }
}
