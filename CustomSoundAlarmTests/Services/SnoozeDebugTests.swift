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

// MARK: - SnoozeDisplayTests（#91-1: チップ＋微調整の表示文言）

struct SnoozeDisplayTests {

    @Test
    func zeroMinutes_showsOff() {
        let text = SnoozeDisplay.text(for: 0)
        #expect(!text.isEmpty)
        #expect(text == String(localized: "snooze_off"))
    }

    @Test
    func quickOptions_containTheirMinutes() {
        // チップの値 1/2/5/10 はいずれも分値を含む文言になる
        for minutes in [1, 2, 5, 10] {
            let text = SnoozeDisplay.text(for: minutes)
            #expect(!text.isEmpty)
            #expect(text.contains("\(minutes)"), "Text for \(minutes) min should contain the number")
        }
    }

    @Test
    func arbitraryValues_areFormatted() {
        // 微調整で選べる任意値（旧選択肢に無い値を含む）
        for minutes in [3, 7, 12, 25, 30] {
            let text = SnoozeDisplay.text(for: minutes)
            #expect(!text.isEmpty)
            #expect(text.contains("\(minutes)"))
        }
    }

    @Test
    func negativeMinutes_showsOffFallback() {
        // 範囲外の値はフォーマットに流れるが空にはならない
        #expect(!SnoozeDisplay.text(for: -1).isEmpty)
    }
}
