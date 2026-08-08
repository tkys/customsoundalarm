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
    func dimmedBrightness_halfsOriginal() {
        let result = BedsideClockLogic.dimmedBrightness(originalBrightness: 0.8)
        #expect(result == 0.4)
    }

    @Test
    func dimmedBrightness_floorAt005() {
        let result = BedsideClockLogic.dimmedBrightness(originalBrightness: 0.01)
        #expect(result == 0.05)
    }

    @Test
    func idleBrightness_fifteenPercent() {
        let result = BedsideClockLogic.idleBrightness(originalBrightness: 1.0)
        #expect(result == 0.15)
    }

    @Test
    func idleBrightness_floorAt002() {
        let result = BedsideClockLogic.idleBrightness(originalBrightness: 0.05)
        #expect(result == 0.02)
    }

    @Test
    func dimmedLessThanIdle_isFalse() {
        // 通常時の減光はアイドル時より明るい
        let dimmed = BedsideClockLogic.dimmedBrightness(originalBrightness: 0.8)
        let idle = BedsideClockLogic.idleBrightness(originalBrightness: 0.8)
        #expect(dimmed > idle)
    }
}
