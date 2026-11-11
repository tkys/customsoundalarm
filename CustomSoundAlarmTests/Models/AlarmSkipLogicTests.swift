import Testing
import Foundation
@testable import CustomSoundAlarm

/// 休み・祝日の純ロジック（#197）。
struct AlarmSkipLogicTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.locale = Locale(identifier: "ja_JP")
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour
        ))!
    }

    private func repeating(_ weekdays: [Int], hour: Int = 7) -> AlarmEntry {
        AlarmEntry(hour: hour, minute: 0, repeatWeekdays: weekdays)
    }

    // MARK: - 日付キー

    @Test
    func dateKeyRoundTrip() {
        let day = date(2026, 11, 12, 23)
        let key = AlarmSkipLogic.dateKey(day, calendar: calendar)
        #expect(key == "2026-11-12")
        #expect(AlarmSkipLogic.date(fromKey: key, calendar: calendar) == date(2026, 11, 12))
    }

    // MARK: - 休む日の曜日

    @Test
    func skippedDay_removesItsWeekdayOnly() {
        var entry = repeating([1, 2, 3, 4, 5, 6, 7])
        entry.skipDates = ["2026-11-11"]  // 水曜
        let now = date(2026, 11, 10, 12)

        let effective = AlarmSkipLogic.effectiveWeekdays(
            for: entry, after: now, calendar: calendar
        )
        #expect(effective == [1, 2, 3, 5, 6, 7])
        #expect(AlarmSkipLogic.skippedWeekdays(for: entry, after: now, calendar: calendar) == [4])
    }

    @Test
    func nextFire_skipsTheSkippedDay() {
        var entry = repeating([4]) // 水曜だけ
        entry.skipDates = ["2026-11-11"]
        let now = date(2026, 11, 10, 12)

        let next = AlarmSkipLogic.nextFireDate(for: entry, after: now, calendar: calendar)
        #expect(next == date(2026, 11, 18, 7))
    }

    @Test
    func nextFire_otherDaysStillRing() {
        var entry = repeating([1, 2, 3, 4, 5, 6, 7])
        entry.skipDates = ["2026-11-11"]
        let now = date(2026, 11, 10, 12)

        let next = AlarmSkipLogic.nextFireDate(for: entry, after: now, calendar: calendar)
        #expect(next == date(2026, 11, 12, 7))
    }

    @Test
    func oneTimeAlarm_onSkippedDay_doesNotFire() {
        var entry = AlarmEntry(hour: 7, minute: 0, repeatWeekdays: [])
        entry.skipDates = ["2026-11-11"]
        let now = date(2026, 11, 10, 12)

        #expect(AlarmSkipLogic.nextFireDate(for: entry, after: now, calendar: calendar) == nil)
    }

    @Test
    func oneTimeAlarm_onOtherDay_stillFires() {
        var entry = AlarmEntry(hour: 7, minute: 0, repeatWeekdays: [])
        entry.skipDates = ["2026-11-12"]
        let now = date(2026, 11, 10, 12)

        #expect(AlarmSkipLogic.nextFireDate(for: entry, after: now, calendar: calendar)
            == date(2026, 11, 11, 7))
    }

    // MARK: - 外した曜日の補完

    @Test
    func coverage_doesNotIncludeSkippedDay() {
        var entry = repeating([1, 2, 3, 4, 5, 6, 7])
        entry.skipDates = ["2026-11-11"]
        let now = date(2026, 11, 10, 12)

        let coverage = AlarmSkipLogic.coverageOccurrences(
            for: entry, after: now, calendar: calendar
        )
        #expect(!coverage.contains { $0.dateKey == "2026-11-11" })
        #expect(coverage.contains { $0.dateKey == "2026-11-18" })
    }

    @Test
    func coverage_includesNormalWeeksBeforeALaterSkip() {
        var entry = repeating([1, 2, 3, 4, 5, 6, 7])
        entry.skipDates = ["2026-12-02"] // 2週間後
        let now = date(2026, 11, 10, 12)

        let keys = AlarmSkipLogic.coverageOccurrences(
            for: entry, after: now, calendar: calendar
        ).map(\.dateKey)
        #expect(keys.contains("2026-11-11"))
        #expect(keys.contains("2026-11-18"))
        #expect(keys.contains("2026-11-25"))
        #expect(!keys.contains("2026-12-02"))
        #expect(keys.contains("2026-12-09"))
    }

    @Test
    func coverage_emptyForSingleWeekdayEntry() {
        // 曜日が1つだけなら、その曜日を外すと本体を .fixed にする（補完は不要）
        var entry = repeating([4])
        entry.skipDates = ["2026-11-11"]
        #expect(AlarmSkipLogic.coverageOccurrences(
            for: entry, after: date(2026, 11, 10, 12), calendar: calendar
        ).isEmpty)
        #expect(AlarmSkipLogic.primaryUsesFixed(
            for: entry, after: date(2026, 11, 10, 12), calendar: calendar
        ))
    }

    @Test
    func coverage_emptyWhenNoWeekdayRemoved() {
        let entry = repeating([4])
        let now = date(2026, 11, 10, 12)
        #expect(AlarmSkipLogic.coverageOccurrences(
            for: entry, after: now, calendar: calendar
        ).isEmpty)
    }

    @Test
    func allWeekdaysSkipped_switchesPrimaryToFixed() {
        var entry = repeating([1, 2, 3, 4, 5, 6, 7])
        entry.skipDates = (0..<7).compactMap { offset in
            Calendar.current.date(byAdding: .day, value: offset, to: Date())
                .map { AlarmSkipLogic.dateKey($0) }
        }
        #expect(AlarmSkipLogic.primaryUsesFixed(for: entry, after: Date()))
    }

    // MARK: - 祝日

    @Test
    func holiday_onRepeatedWeekday_isSkipped() {
        var entry = repeating([2]) // 月曜
        entry.skipsHolidays = true
        let now = date(2026, 11, 1, 12)

        #expect(AlarmSkipLogic.isSkipped(
            date(2026, 11, 23), entry: entry, calendar: calendar
        ))
        #expect(AlarmSkipLogic.skippedWeekdays(
            for: entry, after: now, calendar: calendar
        ) == [2])
    }

    @Test
    func holidayOverride_ringsOnThatHoliday() {
        var entry = repeating([2])
        entry.skipsHolidays = true
        entry.holidayRingOverrides = ["2026-11-23"]

        #expect(!AlarmSkipLogic.isSkipped(
            date(2026, 11, 23), entry: entry, calendar: calendar
        ))
        #expect(AlarmSkipLogic.skippedWeekdays(
            for: entry, after: date(2026, 11, 1), calendar: calendar
        ).isEmpty)
    }

    @Test
    func nextSkippedHoliday_returnsTheNextOneForRepeatedWeekday() {
        var entry = repeating([2])
        entry.skipsHolidays = true
        let next = AlarmSkipLogic.nextSkippedHoliday(
            for: entry, after: date(2026, 11, 1), calendar: calendar
        )
        #expect(next?.dateKey == "2026-11-23")
    }

    @Test
    func nextSkippedHoliday_matchesTheRepeatedWeekday() {
        var entry = repeating([4]) // 水曜
        entry.skipsHolidays = true
        let next = AlarmSkipLogic.nextSkippedHoliday(
            for: entry, after: date(2026, 11, 1), calendar: calendar
        )
        #expect(next != nil)
        if let holiday = next, let date = AlarmSkipLogic.date(
            fromKey: holiday.dateKey, calendar: calendar
        ) {
            #expect(calendar.component(.weekday, from: date) == 4)
        }
    }

    // MARK: - 一覧・案内

    @Test
    func dayGroups_useTheNextFireDate() {
        let morning = AlarmEntry(hour: 7, minute: 0, repeatWeekdays: [4])
        let evening = AlarmEntry(hour: 22, minute: 0, repeatWeekdays: [4])
        let now = date(2026, 11, 10, 12)

        let groups = AlarmSkipLogic.upcomingDayGroups(
            entries: [evening, morning], after: now, calendar: calendar
        )
        #expect(groups.count == 1)
        #expect(groups[0].dateKey == "2026-11-11")
        #expect(groups[0].entries.map(\.hour) == [7, 22])
    }

    @Test
    func activeNotice_showsNextFireAfterTheSkippedDay() {
        var entry = repeating([1, 2, 3, 4, 5, 6, 7])
        entry.skipDates = ["2026-11-12"]
        let notice = AlarmSkipLogic.activeNotice(
            entries: [entry], now: date(2026, 11, 11, 10), calendar: calendar
        )
        #expect(notice?.dateKey == "2026-11-12")
        #expect(notice?.nextFire == date(2026, 11, 13, 7))
    }

    @Test
    func activeNotice_disappearsWhenTheDayHasPassed() {
        var entry = repeating([1, 2, 3, 4, 5, 6, 7])
        entry.skipDates = ["2026-11-12"]
        let notice = AlarmSkipLogic.activeNotice(
            entries: [entry], now: date(2026, 11, 13, 0), calendar: calendar
        )
        #expect(notice == nil)
    }

    @Test
    func fires_onMatchingDate() {
        let entry = repeating([4])
        #expect(AlarmSkipLogic.fires(
            on: date(2026, 11, 11), entry: entry, calendar: calendar
        ))
        #expect(!AlarmSkipLogic.fires(
            on: date(2026, 11, 12), entry: entry, calendar: calendar
        ))
    }

    @Test
    func pruning_dropsPastDates() {
        var entry = repeating([4])
        entry.skipDates = ["2026-11-10", "2026-11-11", "2026-11-12"]
        entry.holidayRingOverrides = ["2026-11-03", "2026-11-23"]
        let pruned = AlarmSkipLogic.pruning(
            entry, now: date(2026, 11, 11, 12), calendar: calendar
        )
        #expect(pruned.skipDates == ["2026-11-11", "2026-11-12"])
        #expect(pruned.holidayRingOverrides == ["2026-11-23"])
    }
}

/// 休みの適用と取り消しが AlarmStore に反映される（#197）。
@MainActor
struct AlarmSkipServiceTests {

    @Test
    func skipDay_addsTheDateAndUndoRemovesIt() async {
        let original = AlarmStore.shared.alarms
        defer { AlarmStore.shared.replaceAll(original) }

        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        let key = AlarmSkipLogic.dateKey(tomorrow, calendar: calendar)
        let entry = AlarmEntry(
            hour: 7,
            minute: 0,
            label: "service-test",
            repeatWeekdays: [1, 2, 3, 4, 5, 6, 7]
        )
        AlarmStore.shared.replaceAll([entry])

        AlarmSkipService.skipDay(tomorrow, entries: [entry])
        #expect(AlarmStore.shared.alarms.first?.skipDates == [key])

        AlarmSkipService.undo(dateKey: key)
        #expect(AlarmStore.shared.alarms.first?.skipDates == [])

        await AlarmScheduler.shared.waitForPendingSync()
    }
}
