import Testing
import Foundation
@testable import CustomSoundAlarm

struct LoudnessNormalizerTests {

    private func approx(_ a: Double, _ b: Double, tolerance: Double = 0.0001) -> Bool {
        abs(a - b) < tolerance
    }

    // MARK: - gainDb

    @Test
    func gainDb_minus7_2_returns6_2() {
        #expect(approx(LoudnessNormalizer.gainDb(forPeakDb: -7.2), 6.2))
    }

    @Test
    func gainDb_zero_returnsZero() {
        #expect(LoudnessNormalizer.gainDb(forPeakDb: 0.0) == 0)
    }

    @Test
    func gainDb_minus1_returnsZero() {
        #expect(LoudnessNormalizer.gainDb(forPeakDb: -1.0) == 0)
    }

    @Test
    func gainDb_minus30_capsAt20() {
        // -1 - (-30) = 29 -> clamp to 20
        #expect(LoudnessNormalizer.gainDb(forPeakDb: -30) == 20)
    }

    @Test
    func gainDb_minus70_silentReturnsZero() {
        // -70 < -60 silent threshold -> 0
        #expect(LoudnessNormalizer.gainDb(forPeakDb: -70) == 0)
        #expect(LoudnessNormalizer.gainDb(forPeakDb: -60.1) == 0)
    }

    @Test
    func gainDb_nil_returnsZero() {
        #expect(LoudnessNormalizer.gainDb(forPeakDb: nil) == 0)
    }

    @Test
    func gainDb_minus60_returnsZeroOrNotSilent() {
        // -60 is threshold inclusive -> should be processed: gain = 59 -> capped 20? Wait -1 - (-60) = 59 -> 20
        // But spec says "ピークが -60 dBFS 未満（無音とみなす）なら何もしない" -> < -60 is silent, -60 itself is not silent
        #expect(LoudnessNormalizer.gainDb(forPeakDb: -60) == 20)
        #expect(LoudnessNormalizer.gainDb(forPeakDb: -59.9) == 20)
    }

    // MARK: - peakDbBucket

    @Test
    func peakDbBucket_silentCases() {
        #expect(LoudnessNormalizer.peakDbBucket(forPeakDb: nil) == "silent")
        #expect(LoudnessNormalizer.peakDbBucket(forPeakDb: -70) == "silent")
        #expect(LoudnessNormalizer.peakDbBucket(forPeakDb: -60.1) == "silent")
        #expect(LoudnessNormalizer.peakDbBucket(forPeakDb: -100) == "silent")
    }

    @Test
    func peakDbBucket_eachBucket() {
        #expect(LoudnessNormalizer.peakDbBucket(forPeakDb: 0) == ">=-1")
        #expect(LoudnessNormalizer.peakDbBucket(forPeakDb: -1) == ">=-1")
        #expect(LoudnessNormalizer.peakDbBucket(forPeakDb: -1.1) == "-1~-3")
        #expect(LoudnessNormalizer.peakDbBucket(forPeakDb: -2) == "-1~-3")
        #expect(LoudnessNormalizer.peakDbBucket(forPeakDb: -3) == "-3~-6")
        #expect(LoudnessNormalizer.peakDbBucket(forPeakDb: -5) == "-3~-6")
        #expect(LoudnessNormalizer.peakDbBucket(forPeakDb: -6) == "-6~-12")
        #expect(LoudnessNormalizer.peakDbBucket(forPeakDb: -10) == "-6~-12")
        #expect(LoudnessNormalizer.peakDbBucket(forPeakDb: -12) == "-6~-12")
        #expect(LoudnessNormalizer.peakDbBucket(forPeakDb: -12.1) == "<-12")
        #expect(LoudnessNormalizer.peakDbBucket(forPeakDb: -30) == "<-12")
    }

    // MARK: - gainDbBucket

    @Test
    func gainDbBucket_boundaries() {
        #expect(LoudnessNormalizer.gainDbBucket(forGainDb: 0) == "0")
        #expect(LoudnessNormalizer.gainDbBucket(forGainDb: 0.1) == "0~3")
        #expect(LoudnessNormalizer.gainDbBucket(forGainDb: 3) == "0~3")
        #expect(LoudnessNormalizer.gainDbBucket(forGainDb: 3.1) == "3~6")
        #expect(LoudnessNormalizer.gainDbBucket(forGainDb: 6) == "3~6")
        #expect(LoudnessNormalizer.gainDbBucket(forGainDb: 6.1) == "6~12")
        #expect(LoudnessNormalizer.gainDbBucket(forGainDb: 12) == "6~12")
        #expect(LoudnessNormalizer.gainDbBucket(forGainDb: 12.1) == "12~20")
        #expect(LoudnessNormalizer.gainDbBucket(forGainDb: 20) == "12~20")
    }
}
