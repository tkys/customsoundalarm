import Foundation
import Testing

@testable import CustomSoundAlarm

/// ワードクロック（#72 Phase1）の純粋ロジックのテスト
struct WordClockLogicTests {

    // MARK: - roundedMinute

    @Test
    func roundedMinute_floorToFive() {
        #expect(WordClockLogic.roundedMinute(0) == 0)
        #expect(WordClockLogic.roundedMinute(4) == 0)
        #expect(WordClockLogic.roundedMinute(5) == 5)
        #expect(WordClockLogic.roundedMinute(23) == 20)
        #expect(WordClockLogic.roundedMinute(55) == 55)
        #expect(WordClockLogic.roundedMinute(59) == 55)
    }

    // MARK: - minuteIndex

    @Test
    func minuteIndex_boundaries() {
        // 0 → 0 (ちょうど), 4 → 0, 5 → 1 (五分), 59 → 11 (五十五分)
        #expect(WordClockLogic.minuteIndex(minute: 0) == 0)
        #expect(WordClockLogic.minuteIndex(minute: 4) == 0)
        #expect(WordClockLogic.minuteIndex(minute: 5) == 1)
        #expect(WordClockLogic.minuteIndex(minute: 54) == 10)
        #expect(WordClockLogic.minuteIndex(minute: 55) == 11)
        #expect(WordClockLogic.minuteIndex(minute: 59) == 11)
    }

    @Test
    func minuteIndex_isStepOfFive() {
        for minute in 0..<60 {
            #expect(WordClockLogic.minuteIndex(minute: minute) == minute / 5)
        }
    }

    // MARK: - hourIndex

    @Test
    func hourIndex_boundaries() {
        // 0時 → 11 (十二時), 12時 → 11, 13時 → 0 (一時)
        #expect(WordClockLogic.hourIndex(hour: 0) == 11)
        #expect(WordClockLogic.hourIndex(hour: 12) == 11)
        #expect(WordClockLogic.hourIndex(hour: 1) == 0)
        #expect(WordClockLogic.hourIndex(hour: 13) == 0)
        #expect(WordClockLogic.hourIndex(hour: 11) == 10)
        #expect(WordClockLogic.hourIndex(hour: 23) == 10)
    }

    @Test
    func hourIndex_roundTrip() {
        for hour in 0..<24 {
            #expect(WordClockLogic.hourIndex(hour: hour) == (hour % 12 + 11) % 12)
        }
    }
}