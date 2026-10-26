import Testing
import Foundation
@testable import CustomSoundAlarm

struct LookaheadLimiterTests {

    private func sine(amplitude: Float, seconds: Double = 1) -> [Float] {
        let count = Int(44_100 * seconds)
        return (0..<count).map { index in
            Float(Double(amplitude) * sin(2 * Double.pi * 1000 * Double(index) / 44_100))
        }
    }

    @Test
    func process_capsPeakAtMinus1() {
        let result = LookaheadLimiter.process(samples: sine(amplitude: 1.0), gainDb: 0)
        #expect(result.peak <= 0.8915, "peak was \(result.peak)")
    }

    @Test
    func process_quietSignalHasNoReduction() {
        let result = LookaheadLimiter.process(samples: sine(amplitude: 0.2), gainDb: 0)
        #expect(result.averageReductionDb < 0.001)
        #expect(result.peak <= 0.2 + 0.001)
    }

    @Test
    func process_gainPushesIntoLimiter() {
        let result = LookaheadLimiter.process(samples: sine(amplitude: 0.5), gainDb: 12)
        #expect(result.peak <= 0.8915, "peak was \(result.peak)")
        #expect(result.averageReductionDb > 1.0)
    }

    @Test
    func process_bypassDoesNotLimit() {
        let result = LookaheadLimiter.process(
            samples: sine(amplitude: 0.5),
            gainDb: 12,
            bypass: true
        )
        #expect(result.peak > 0.8915)
    }
}
