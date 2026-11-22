import Testing
import Foundation
@testable import CustomSoundAlarm

/// 画面に出す時刻の書式（#283）。
struct AlarmTimeFormatTests {

    private func locale(_ id: String, _ cycle: Locale.HourCycle? = nil) -> Locale {
        let parts = id.split(separator: "_")
        var components = Locale.Components(
            languageCode: Locale.LanguageCode(String(parts[0]))
        )
        if parts.count > 1 {
            components.region = Locale.Region(String(parts[1]))
        }
        components.hourCycle = cycle
        return Locale(components: components)
    }

    private func display(_ hour: Int, _ minute: Int, _ locale: Locale) -> String {
        AlarmTimeFormat.display(
            hour: hour,
            minute: minute,
            locale: locale,
            calendar: Calendar(identifier: .gregorian)
        )
    }

    /// en-US の AM／PM 前は U+202F（narrow no-break space）。比較しやすいよう空白にそろえる。
    private func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\u{202F}", with: " ")
    }

    @Test
    func japaneseUses24HourWithoutLeadingZero() {
        let ja = locale("ja_JP")
        #expect(display(5, 1, ja) == "5:01")
        #expect(display(17, 5, ja) == "17:05")
        #expect(display(0, 5, ja) == "0:05")
    }

    @Test
    func englishUSUses12HourWithAMPM() {
        let us = locale("en_US")
        #expect(normalized(display(5, 1, us)) == "5:01 AM")
        #expect(normalized(display(17, 30, us)) == "5:30 PM")
        #expect(normalized(display(0, 0, us)) == "12:00 AM")
        #expect(normalized(display(12, 0, us)) == "12:00 PM")
    }

    @Test
    func englishGBUses24HourWithLeadingZero() {
        let gb = locale("en_GB")
        #expect(display(5, 1, gb) == "05:01")
        #expect(display(17, 30, gb) == "17:30")
    }

    @Test
    func englishUSForced24HourIgnoresAMPM() {
        let us24 = locale("en_US", .zeroToTwentyThree)
        #expect(display(5, 1, us24) == "05:01")
        #expect(display(17, 30, us24) == "17:30")
    }

    @Test
    func partsPutAMPMAfterTheDigitsInEnglish() {
        let parts = AlarmTimeFormat.parts(
            hour: 17,
            minute: 5,
            locale: locale("en_US"),
            calendar: Calendar(identifier: .gregorian)
        )
        #expect(parts.time == "5:05")
        #expect(parts.period == "PM")
        #expect(parts.periodFirst == false)
        #expect(parts.displayText == "5:05 PM")
    }

    @Test
    func partsPutPeriodBeforeTheDigitsInJapanese12Hour() {
        let parts = AlarmTimeFormat.parts(
            hour: 17,
            minute: 5,
            locale: locale("ja_JP", .oneToTwelve),
            calendar: Calendar(identifier: .gregorian)
        )
        #expect(parts.time == "5:05")
        #expect(parts.period == "午後")
        #expect(parts.periodFirst == true)
        #expect(parts.displayText == "午後5:05")
    }

    @Test
    func partsHaveNoPeriodIn24Hour() {
        let parts = AlarmTimeFormat.parts(
            hour: 17,
            minute: 5,
            locale: locale("ja_JP"),
            calendar: Calendar(identifier: .gregorian)
        )
        #expect(parts.time == "17:05")
        #expect(parts.period == nil)
        #expect(parts.displayText == "17:05")
    }

    @Test
    func entryKeepsInternalTimeString() {
        let entry = AlarmEntry(hour: 5, minute: 1, label: "")
        #expect(entry.timeString == "05:01")
    }
}
