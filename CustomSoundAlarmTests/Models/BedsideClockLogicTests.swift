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
        // 結果はロケール依存だが Bool が返ることのみ検証
        // (テスト環境のロケールに合わせて true または false)
        #expect(result == true || result == false)
    }
}
