import Foundation

/// 自前の先読みリミッタ（純 Swift・#134）。
///
/// - 上限 −1 dBFS
/// - 先読み 5ms（必要ゲインの ±5ms 最小値）
/// - アタック即時・リリース 80ms の指数回復
enum LookaheadLimiter {

    struct Result: Equatable, Sendable {
        let samples: [Float]
        /// リミッタのゲイン係数の時間平均（dB）
        let averageReductionDb: Double
        let peak: Float
    }

    static let ceilingLinear: Float = 0.891 // -1 dBFS
    static let lookaheadSeconds: Double = 0.005
    static let releaseSeconds: Double = 0.08

    /// 入力にゲインをかけ、先読みリミッタを適用する。
    static func process(
        samples: [Float],
        gainDb: Double,
        sampleRate: Double = 44_100,
        bypass: Bool = false
    ) -> Result {
        guard !samples.isEmpty else {
            return Result(samples: [], averageReductionDb: 0, peak: 0)
        }

        let gain = Float(pow(10.0, gainDb / 20.0))

        if bypass {
            let output = samples.map { $0 * gain }
            let peak = output.reduce(Float(0)) { max($0, abs($1)) }
            return Result(samples: output, averageReductionDb: 0, peak: peak)
        }

        let count = samples.count
        let lookahead = max(1, Int(sampleRate * lookaheadSeconds))

        // 各サンプルに必要なゲイン（上限を超える場合のみ 1 未満）
        var needed = [Float](repeating: 1, count: count)
        for index in 0..<count {
            let value = abs(samples[index] * gain)
            needed[index] = value > ceilingLinear ? ceilingLinear / value : 1
        }

        // ±lookahead の最小値を単調キューで求める
        var target = [Float](repeating: 1, count: count)
        var deque = [Int]()
        var head = 0

        func push(_ index: Int) {
            while deque.count > head && needed[deque[deque.count - 1]] >= needed[index] {
                deque.removeLast()
            }
            deque.append(index)
        }

        for index in 0...min(count - 1, lookahead) {
            push(index)
        }

        for index in 0..<count {
            if index > 0 {
                let add = index + lookahead
                if add < count {
                    push(add)
                }
                let removeBefore = index - lookahead
                while head < deque.count && deque[head] < removeBefore {
                    head += 1
                }
            }
            target[index] = head < deque.count ? needed[deque[head]] : 1
        }

        // アタック即時・リリース 80ms
        let releaseCoefficient = Float(exp(-1.0 / (releaseSeconds * sampleRate)))
        var current: Float = 1
        var sumLinearGain = 0.0
        var peak: Float = 0
        var output = [Float](repeating: 0, count: count)

        for index in 0..<count {
            let targetGain = target[index]
            current = targetGain < current
                ? targetGain
                : releaseCoefficient * current + (1 - releaseCoefficient) * targetGain
            let appliedGain = min(current, targetGain)
            let value = samples[index] * gain * appliedGain
            output[index] = value
            peak = max(peak, abs(value))
            sumLinearGain += Double(appliedGain)
        }

        let meanGain = sumLinearGain / Double(count)
        return Result(
            samples: output,
            averageReductionDb: -20 * log10(max(meanGain, 1e-6)),
            peak: peak
        )
    }
}
