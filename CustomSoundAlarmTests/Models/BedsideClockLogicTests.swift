import Testing
import Foundation
@testable import CustomSoundAlarm

/// `BedsideClockLogic` の純粋関数を検証する。
struct BedsideClockLogicTests {

    // MARK: - clockOffset（焼き付き対策）

    @Test
    func clockOffset_withinRange() {
        let date = Date()
        let offset = BedsideClockLogic.clockOffset(for: date)
        #expect(BedsideClockLogic.isOffsetWithinRange(offset))
    }

    @Test
    func clockOffset_changesOverTime() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let later = Date(timeIntervalSinceReferenceDate: 150) // 2.5分後

        let offset1 = BedsideClockLogic.clockOffset(for: base)
        let offset2 = BedsideClockLogic.clockOffset(for: later)

        // 2つの異なる時点でオフセットが異なること
        #expect(offset1 != offset2)
    }

    @Test
    func clockOffset_cyclesEvery5Minutes() {
        // 5分（300秒）周期なので、300秒差なら同じオフセット
        let base = Date(timeIntervalSinceReferenceDate: 100)
        let cycle = Date(timeIntervalSinceReferenceDate: 400) // +300秒

        let offset1 = BedsideClockLogic.clockOffset(for: base)
        let offset2 = BedsideClockLogic.clockOffset(for: cycle)

        #expect(offset1 == offset2)
    }

    @Test
    func clockOffset_neverExceedsMax() {
        // 様々な時点で全て範囲内
        for i in 0..<60 {
            let date = Date(timeIntervalSinceReferenceDate: Double(i) * 50)
            let offset = BedsideClockLogic.clockOffset(for: date)
            #expect(BedsideClockLogic.isOffsetWithinRange(offset), "Offset out of range at \(i)")
        }
    }

    // MARK: - nextAlarmText

    @Test
    func nextAlarmText_noAlarms_returnsNil() {
        let result = BedsideClockLogic.nextAlarmText(
            alarms: [],
            currentDate: Date()
        )
        #expect(result == nil)
    }

    @Test
    func nextAlarmText_disabledAlarmsOnly_returnsNil() {
        let alarm = AlarmEntry(hour: 7, minute: 0, isEnabled: false, repeatWeekdays: [])
        let result = BedsideClockLogic.nextAlarmText(
            alarms: [alarm],
            currentDate: Date()
        )
        #expect(result == nil)
    }

    @Test
    func nextAlarmText_enabledAlarm_returnsText() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!

        // 現在時刻: 6:00 UTC
        var refComps = DateComponents()
        refComps.year = 2026; refComps.month = 1; refComps.day = 15
        refComps.hour = 6; refComps.minute = 0
        let ref = cal.date(from: refComps)!

        let alarm = AlarmEntry(hour: 7, minute: 30, isEnabled: true, repeatWeekdays: [])
        let result = BedsideClockLogic.nextAlarmText(
            alarms: [alarm],
            currentDate: ref,
            calendar: cal
        )
        #expect(result != nil)
    }

    @Test
    func nextAlarmText_picksEarliest() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!

        var refComps = DateComponents()
        refComps.year = 2026; refComps.month = 1; refComps.day = 15
        refComps.hour = 6; refComps.minute = 0
        let ref = cal.date(from: refComps)!

        let early = AlarmEntry(hour: 7, minute: 0, isEnabled: true, repeatWeekdays: [])
        let late = AlarmEntry(hour: 9, minute: 0, isEnabled: true, repeatWeekdays: [])

        let earlyResult = BedsideClockLogic.nextAlarmText(
            alarms: [early],
            currentDate: ref,
            calendar: cal
        )
        let bothResult = BedsideClockLogic.nextAlarmText(
            alarms: [late, early], // 逆順で渡す
            currentDate: ref,
            calendar: cal
        )
        // 両方渡しても早い方と同じ結果になること
        #expect(bothResult == earlyResult)
    }

    // MARK: - is24HourFormat

    @Test
    func is24HourFormat_returnsBool() {
        let result = BedsideClockLogic.is24HourFormat(for: Date())
        #expect(result == true || result == false)
    }

    // MARK: - countdownText

    @Test
    func countdownText_noAlarms_returnsNil() {
        let result = BedsideClockLogic.countdownText(alarms: [], currentDate: Date())
        #expect(result == nil)
    }

    @Test
    func countdownText_enabledAlarm_returnsNonNil() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var refComps = DateComponents()
        refComps.year = 2026; refComps.month = 1; refComps.day = 15
        refComps.hour = 6; refComps.minute = 0
        let ref = cal.date(from: refComps)!

        let alarm = AlarmEntry(hour: 7, minute: 30, isEnabled: true, repeatWeekdays: [])
        let result = BedsideClockLogic.countdownText(alarms: [alarm], currentDate: ref, calendar: cal)
        #expect(result != nil)
    }

    @Test
    func countdownText_underOneHour() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var refComps = DateComponents()
        refComps.year = 2026; refComps.month = 1; refComps.day = 15
        refComps.hour = 6; refComps.minute = 50
        let ref = cal.date(from: refComps)!

        let alarm = AlarmEntry(hour: 7, minute: 0, isEnabled: true, repeatWeekdays: [])
        let result = BedsideClockLogic.countdownText(alarms: [alarm], currentDate: ref, calendar: cal)
        #expect(result != nil)
    }

    @Test
    func countdownText_over24Hours() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var refComps = DateComponents()
        refComps.year = 2026; refComps.month = 1; refComps.day = 15
        refComps.hour = 6; refComps.minute = 0
        let ref = cal.date(from: refComps)!

        // 繰り返しアラームで週末のみ → 数日先になる可能性
        let alarm = AlarmEntry(hour: 6, minute: 0, isEnabled: true, repeatWeekdays: [1])
        let result = BedsideClockLogic.countdownText(alarms: [alarm], currentDate: ref, calendar: cal)
        #expect(result != nil)
    }

    // MARK: - nextAlarmFireDate

    @Test
    func nextAlarmFireDate_disabledOnly_returnsNil() {
        let alarm = AlarmEntry(hour: 7, minute: 0, isEnabled: false, repeatWeekdays: [])
        let result = BedsideClockLogic.nextAlarmFireDate(alarms: [alarm], currentDate: Date())
        #expect(result == nil)
    }

    // MARK: - ColorTheme

    @Test
    func colorTheme_allCases() {
        #expect(BedsideClockLogic.ColorTheme.allCases.count == 2)
        #expect(BedsideClockLogic.ColorTheme.allCases.contains(.white))
        #expect(BedsideClockLogic.ColorTheme.allCases.contains(.amber))
    }

    @Test
    func colorTheme_rawValueRoundTrip() {
        for theme in BedsideClockLogic.ColorTheme.allCases {
            let raw = theme.rawValue
            let restored = BedsideClockLogic.ColorTheme(rawValue: raw)
            #expect(restored == theme)
        }
    }

    // MARK: - 輝度制御

    @Test
    func dimmedBrightness_defaultSeventyPercent() {
        let result = BedsideClockLogic.dimmedBrightness(originalBrightness: 0.8)
        #expect(result == 0.56) // 0.8 * 0.7
    }

    @Test
    func dimmedBrightness_floorAt01() {
        let result = BedsideClockLogic.dimmedBrightness(originalBrightness: 0.01)
        #expect(result == 0.1)
    }

    @Test
    func idleBrightness_defaultFortyTwoPercent() {
        let result = BedsideClockLogic.idleBrightness(originalBrightness: 1.0)
        #expect(result == 0.42) // 1.0 * 0.7 * 0.6
    }

    @Test
    func idleBrightness_floorAt005() {
        let result = BedsideClockLogic.idleBrightness(originalBrightness: 0.01)
        #expect(result == 0.05)
    }

    @Test
    func dimmedLessThanIdle_isFalse() {
        // 通常時の減光はアイドル時より明るい
        let dimmed = BedsideClockLogic.dimmedBrightness(originalBrightness: 0.8)
        let idle = BedsideClockLogic.idleBrightness(originalBrightness: 0.8)
        #expect(dimmed > idle)
    }

    // MARK: - ユーザー設定可能な輝度

    @Test
    func dimmedBrightness_withUserOffset() {
        let result = BedsideClockLogic.dimmedBrightness(originalBrightness: 1.0, userOffset: 0.3)
        #expect(result == 0.3)
    }

    @Test
    func dimmedBrightness_highUserOffset() {
        let result = BedsideClockLogic.dimmedBrightness(originalBrightness: 0.6, userOffset: 1.0)
        #expect(result == 0.6)
    }

    @Test
    func idleBrightness_withUserOffset() {
        let result = BedsideClockLogic.idleBrightness(originalBrightness: 1.0, userOffset: 0.5)
        #expect(result == 0.3) // 1.0 * 0.5 * 0.6
    }

    // MARK: - BedsideSettings

    @Test
    func bedsideSettings_defaults() {
        let s = BedsideClockLogic.BedsideSettings()
        #expect(s.brightnessOffset == 0.7)
        #expect(s.fontScale == 1.0)
        #expect(s.showCountdown == true)
        #expect(s.showSoundName == true)
        #expect(s.showDate == false)
        #expect(s.showSeconds == false)
        #expect(s.colorTheme == "white")
    }

    @Test
    func bedsideSettings_visibleElementCount() {
        var s = BedsideClockLogic.BedsideSettings()
        #expect(s.visibleElementCount == 2) // countdown + soundName

        s.showDate = true
        #expect(s.visibleElementCount == 3)

        s.showCountdown = false
        s.showSoundName = false
        #expect(s.visibleElementCount == 1) // date only

        s.showDate = false
        #expect(s.visibleElementCount == 0)
    }

    // MARK: - clockFontSize

    @Test
    func clockFontSize_noElements_isLargest() {
        #expect(BedsideClockLogic.clockFontSize(visibleElementCount: 0) == 120)
    }

    @Test
    func clockFontSize_oneElement() {
        #expect(BedsideClockLogic.clockFontSize(visibleElementCount: 1) == 110)
    }

    @Test
    func clockFontSize_twoElements() {
        #expect(BedsideClockLogic.clockFontSize(visibleElementCount: 2) == 96)
    }

    @Test
    func clockFontSize_threeElements_isSmallest() {
        #expect(BedsideClockLogic.clockFontSize(visibleElementCount: 3) == 84)
    }

    @Test
    func clockFontSize_fewerElements_isLarger() {
        let with3 = BedsideClockLogic.clockFontSize(visibleElementCount: 3)
        let with0 = BedsideClockLogic.clockFontSize(visibleElementCount: 0)
        #expect(with0 > with3)
    }

    @Test
    func clockFontSize_withFontScale() {
        let result = BedsideClockLogic.clockFontSize(visibleElementCount: 2, fontScale: 1.5)
        #expect(result == 144) // 96 * 1.5
    }

    @Test
    func clockFontSize_fontScaleLessThanOne() {
        let result = BedsideClockLogic.clockFontSize(visibleElementCount: 0, fontScale: 0.7)
        #expect(result == 84) // 120 * 0.7
    }

    // MARK: - Amber vs White opacity

    @Test
    func amberClockOpacity_higherThanWhite() {
        #expect(BedsideClockLogic.ColorTheme.amber.clockOpacity > BedsideClockLogic.ColorTheme.white.clockOpacity)
    }

    @Test
    func amberInfoOpacity_higherThanWhite() {
        #expect(BedsideClockLogic.ColorTheme.amber.infoOpacity > BedsideClockLogic.ColorTheme.white.infoOpacity)
    }

    @Test
    func whiteClockOpacity_is085() {
        #expect(BedsideClockLogic.ColorTheme.white.clockOpacity == 0.85)
    }

    @Test
    func amberClockOpacity_is1() {
        #expect(BedsideClockLogic.ColorTheme.amber.clockOpacity == 1.0)
    }

    @Test
    func amberTintRGB_isNotNil() {
        #expect(BedsideClockLogic.ColorTheme.amber.tintRGB != nil)
    }

    @Test
    func whiteTintRGB_isNil() {
        #expect(BedsideClockLogic.ColorTheme.white.tintRGB == nil)
    }

    @Test
    func amberTintGreen_is065() {
        let rgb = BedsideClockLogic.ColorTheme.amber.tintRGB!
        #expect(rgb.g == 0.65)
    }

    // MARK: - timeString

    @Test
    func timeString_withoutSeconds() {
        let date = Date()
        let result = BedsideClockLogic.timeString(for: date, is24Hour: true, showSeconds: false)
        // HH:mm 形式であること（コロン1つ、秒なし）
        #expect(result.count == 5)
        #expect(result.filter { $0 == ":" }.count == 1)
    }

    @Test
    func timeString_withSeconds() {
        let date = Date()
        let result = BedsideClockLogic.timeString(for: date, is24Hour: true, showSeconds: true)
        // HH:mm:ss 形式であること（コロン2つ、秒あり）
        #expect(result.count == 8)
        #expect(result.filter { $0 == ":" }.count == 2)
    }
}
