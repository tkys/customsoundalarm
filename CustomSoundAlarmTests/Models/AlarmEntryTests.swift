import Testing
import Foundation
@testable import CustomSoundAlarm

/// `AlarmEntry` の「次回発火予定」と「複製」ロジックを SDK 非依存で検証する。
/// 決定性のため `Calendar(identifier: .gregorian)` + UTC を使用する。
struct AlarmEntryTests {

    /// テスト用の固定カレンダー（ロケール/タイムゾーン非依存）
    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// yyyy-MM-dd HH:mm を UTC で構築
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d
        c.hour = h; c.minute = mi; c.second = 0
        return Self.cal.date(from: c)!
    }

    // MARK: - nextFireDate: 一回限り（repeatWeekdays 空）

    @Test
    func oneShot_timeInFutureToday_firesToday() {
        // 2024-01-15 は月曜。基準 10:00、アラーム 14:30 → 当日 14:30
        let ref = date(2024, 1, 15, 10, 0)
        let alarm = AlarmEntry(hour: 14, minute: 30, repeatWeekdays: [])

        let fire = alarm.nextFireDate(from: ref, calendar: Self.cal)

        #expect(fire == date(2024, 1, 15, 14, 30))
    }

    @Test
    func oneShot_timeInPastToday_firesTomorrow() {
        // 基準 10:00、アラーム 07:00（過ぎた）→ 翌日 07:00
        let ref = date(2024, 1, 15, 10, 0)
        let alarm = AlarmEntry(hour: 7, minute: 0, repeatWeekdays: [])

        let fire = alarm.nextFireDate(from: ref, calendar: Self.cal)

        #expect(fire == date(2024, 1, 16, 7, 0))
    }

    @Test
    func oneShot_disabled_returnsNil() {
        let ref = date(2024, 1, 15, 10, 0)
        let alarm = AlarmEntry(hour: 14, minute: 30, isEnabled: false, repeatWeekdays: [])

        #expect(alarm.nextFireDate(from: ref, calendar: Self.cal) == nil)
    }

    // MARK: - nextFireDate: 繰り返し（repeatWeekdays あり）

    @Test
    func repeating_todayMatchingAndFuture_firesToday() {
        // 2024-01-15 は月曜(weekday=2)。基準 10:00、アラーム 14:30 → 当日 14:30
        let ref = date(2024, 1, 15, 10, 0)
        let alarm = AlarmEntry(hour: 14, minute: 30, repeatWeekdays: [2])

        let fire = alarm.nextFireDate(from: ref, calendar: Self.cal)

        #expect(fire == date(2024, 1, 15, 14, 30))
    }

    @Test
    func repeating_todayMatchingButPast_firesNextWeek() {
        // 月曜(2) 繰り返し、基準 10:00、アラーム 07:00（過ぎた）→ 翌週 月曜 07:00
        let ref = date(2024, 1, 15, 10, 0)
        let alarm = AlarmEntry(hour: 7, minute: 0, repeatWeekdays: [2])

        let fire = alarm.nextFireDate(from: ref, calendar: Self.cal)

        #expect(fire == date(2024, 1, 22, 7, 0))
    }

    @Test
    func repeating_todayNotMatching_firesNextMatchingDay() {
        // 基準 月曜 2024-01-15 10:00、水曜(4) 繰り返し → 水曜 2024-01-17 14:30
        let ref = date(2024, 1, 15, 10, 0)
        let alarm = AlarmEntry(hour: 14, minute: 30, repeatWeekdays: [4])

        let fire = alarm.nextFireDate(from: ref, calendar: Self.cal)

        #expect(fire == date(2024, 1, 17, 14, 30))
    }

    @Test
    func repeating_multipleWeekdays_picksSoonest() {
        // 月(2)・水(4) 繰り返し、基準 月曜 10:00、アラーム 14:30（未来）→ 当日 月曜 14:30
        let ref = date(2024, 1, 15, 10, 0)
        let alarm = AlarmEntry(hour: 14, minute: 30, repeatWeekdays: [2, 4])

        let fire = alarm.nextFireDate(from: ref, calendar: Self.cal)

        #expect(fire == date(2024, 1, 15, 14, 30))
    }

    @Test
    func repeating_multipleWeekdays_picksSoonestAcrossDays() {
        // 水(4)・金(6) 繰り返し、基準 月曜 10:00 → 水曜が先（金より早い）
        let ref = date(2024, 1, 15, 10, 0)
        let alarm = AlarmEntry(hour: 14, minute: 30, repeatWeekdays: [4, 6])

        let fire = alarm.nextFireDate(from: ref, calendar: Self.cal)

        #expect(fire == date(2024, 1, 17, 14, 30))
    }

    @Test
    func repeating_sundayWraparound() {
        // 金(6)・日(1) 繰り返し、基準 土曜 2024-01-20 10:00 → 日曜 2024-01-21 09:00
        let ref = date(2024, 1, 20, 10, 0)
        let alarm = AlarmEntry(hour: 9, minute: 0, repeatWeekdays: [6, 1])

        let fire = alarm.nextFireDate(from: ref, calendar: Self.cal)

        #expect(fire == date(2024, 1, 21, 9, 0))
    }

    // MARK: - nextFireDate: 異常系

    @Test
    func invalidHour_returnsNil() {
        let ref = date(2024, 1, 15, 10, 0)
        let alarm = AlarmEntry(hour: 25, minute: 0)

        #expect(alarm.nextFireDate(from: ref, calendar: Self.cal) == nil)
    }

    @Test
    func invalidMinute_returnsNil() {
        let ref = date(2024, 1, 15, 10, 0)
        let alarm = AlarmEntry(hour: 7, minute: 60)

        #expect(alarm.nextFireDate(from: ref, calendar: Self.cal) == nil)
    }

    @Test
    func repeating_invalidWeekdayFilteredOut_returnsNilWhenAllInvalid() {
        let ref = date(2024, 1, 15, 10, 0)
        let alarm = AlarmEntry(hour: 7, minute: 0, repeatWeekdays: [0, 8, 9])

        #expect(alarm.nextFireDate(from: ref, calendar: Self.cal) == nil)
    }

    // MARK: - duplicated()

    @Test
    func duplicated_createsIndependentCopyWithNewId() {
        let original = AlarmEntry(
            id: UUID(),
            hour: 7, minute: 30,
            isEnabled: false, // 意図的に false
            label: "朝のアラーム",
            repeatWeekdays: [2, 4, 6],
            soundFileName: "abc.caf"
        )

        let copy = original.duplicated()

        #expect(copy.id != original.id, "複製は新しい id を持つべき")
        #expect(copy.isEnabled == true, "複製は常に有効")
        #expect(copy.hour == 7)
        #expect(copy.minute == 30)
        #expect(copy.label == "朝のアラーム")
        #expect(copy.repeatWeekdays == [2, 4, 6])
        #expect(copy.soundFileName == "abc.caf")
    }

    @Test
    func duplicated_doesNotMutateOriginal() {
        // AlarmEntry は値型なので duplicated() が新しいインスタンスを返す以上、
        // 元は不変。主要フィールドが変わっていないことを確認する。
        let original = AlarmEntry(
            hour: 6, minute: 0,
            isEnabled: true,
            label: "Original",
            repeatWeekdays: [1],
            soundFileName: "x.caf"
        )
        let originalId = original.id

        _ = original.duplicated()

        #expect(original.id == originalId)
        #expect(original.isEnabled == true)
        #expect(original.hour == 6)
        #expect(original.label == "Original")
        #expect(original.repeatWeekdays == [1])
    }
}
