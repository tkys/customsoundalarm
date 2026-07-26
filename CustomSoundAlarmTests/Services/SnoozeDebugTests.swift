import Testing
import Foundation
@testable import CustomSoundAlarm

// MARK: - snoozeIntervalTests

struct snoozeIntervalTests {

    @Test
    func normalMode_convertsMinutesToSeconds() {
        #expect(snoozeInterval(minutes: 5, useSeconds: false) == 300)
        #expect(snoozeInterval(minutes: 1, useSeconds: false) == 60)
        #expect(snoozeInterval(minutes: 30, useSeconds: false) == 1800)
        #expect(snoozeInterval(minutes: 0, useSeconds: false) == 0)
    }

    @Test
    func debugSecondsMode_treatsMinutesAsSeconds() {
        #expect(snoozeInterval(minutes: 5, useSeconds: true) == 5)
        #expect(snoozeInterval(minutes: 1, useSeconds: true) == 1)
        #expect(snoozeInterval(minutes: 30, useSeconds: true) == 30)
        #expect(snoozeInterval(minutes: 0, useSeconds: true) == 0)
    }
}

// MARK: - SnoozeOptionTests

struct SnoozeOptionTests {

    @Test
    func allContainsOneMinuteOption() {
        let minutes = SnoozeOption.all.map(\.minutes)
        #expect(minutes.contains(1))
    }

    @Test
    func allContainsExpectedMinutes() {
        let expected = [0, 1, 5, 9, 10, 15, 20, 30]
        #expect(SnoozeOption.all.map(\.minutes) == expected)
    }

    @Test
    func labelForOneMinute_returnsNonEmpty() {
        let label = SnoozeOption.label(for: 1)
        #expect(!label.isEmpty)
    }

    @Test
    func labelForKnownValue_returnsNonEmpty() {
        for option in SnoozeOption.all {
            let label = SnoozeOption.label(for: option.minutes)
            #expect(!label.isEmpty, "Label should not be empty for \(option.minutes) min")
        }
    }

    @Test
    func labelForUnknownValue_fallsBackToNine() {
        let label = SnoozeOption.label(for: 99)
        #expect(!label.isEmpty)
    }
}
