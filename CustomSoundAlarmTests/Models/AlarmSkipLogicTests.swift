import Testing
import Foundation
import UIKit
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
    func coverage_singleWeekdayAllSkipped_coversAfterThePrimary() {
        // 曜日が1つだけでも、休みのあとの70日分を補完する（#197 レビュー）
        var entry = repeating([4])
        entry.skipDates = ["2026-11-11"]
        let now = date(2026, 11, 10, 12)
        #expect(AlarmSkipLogic.primaryUsesFixed(for: entry, after: now, calendar: calendar))
        let coverage = AlarmSkipLogic.coverageOccurrences(
            for: entry, after: now, calendar: calendar
        )
        // 11/18 は本体（.fixed）が受け持ち、11/25 から補完
        #expect(coverage.first?.dateKey == "2026-11-25")
        #expect(!coverage.contains { $0.dateKey == "2026-11-11" })
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
@Suite(.serialized)
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

/// レビュー対応の追加テスト（#197）。
extension AlarmSkipLogicTests {

    @Test
    func pruning_keepsTheSkipDisabledMarker() {
        var entry = repeating([4])
        entry.isEnabled = false
        entry.skipDisabledDate = "2026-11-10"
        let pruned = AlarmSkipLogic.pruning(
            entry, now: date(2026, 11, 12, 12), calendar: calendar
        )
        #expect(!pruned.isEnabled)
        #expect(pruned.skipDisabledDate == "2026-11-10")
        #expect(pruned.skipDates.isEmpty)
    }

    @Test
    func allWeekdaysRemoved_coversTheHorizonAfterTheBreak() {
        var entry = repeating([2, 3, 4, 5, 6]) // 月〜金
        entry.skipDates = (27...31).map { "2026-12-\(String(format: "%02d", $0))" }
            + (1...4).map { "2027-01-\(String(format: "%02d", $0))" }
        let now = date(2026, 12, 26, 12)

        #expect(AlarmSkipLogic.primaryUsesFixed(
            for: entry, after: now, calendar: calendar
        ))
        let coverage = AlarmSkipLogic.coverageOccurrences(
            for: entry, after: now, calendar: calendar
        )
        #expect(!coverage.isEmpty)
        let primary = try? #require(AlarmSkipLogic.nextFireDate(
            for: entry, after: now, calendar: calendar
        ))
        let all = Set(coverage.map(\.dateKey))
            .union(primary.map { [AlarmSkipLogic.dateKey($0, calendar: calendar)] } ?? [])
        // 休み明けの 1/5 から、70日分の平日が登録される
        for key in ["2027-01-05", "2027-01-06", "2027-01-07", "2027-01-08", "2027-01-12"] {
            #expect(all.contains(key), "missing \(key)")
        }
        // 休みの日は入らない
        #expect(!all.contains("2027-01-01"))
    }

    @Test
    func limitedCoverage_keepsTheEarliestAndDefersTheRest() {
        let base = date(2026, 11, 20)
        let items = (0..<100).map { index in
            AlarmSkipLogic.CoverageItem(
                entryID: UUID(),
                coverage: AlarmSkipLogic.Coverage(
                    dateKey: "2026-11-\(String(format: "%02d", 20 + index % 10))",
                    date: base.addingTimeInterval(Double(index) * 86400)
                )
            )
        }
        let limited = AlarmSkipLogic.limitedCoverage(items, limit: 80)
        #expect(limited.selected.count == 80)
        #expect(limited.deferred == 20)
        #expect(limited.selected.first?.coverage.date == items.first?.coverage.date)
        #expect(limited.selected.last!.coverage.date < items[80].coverage.date)
    }

    @Test
    func reconcileOnStop_oncePerDayForHolidayOrSkipSettings() {
        var holiday = repeating([2])
        holiday.skipsHolidays = true
        let today = date(2026, 11, 12, 8)
        #expect(AlarmSkipLogic.shouldReconcileOnStop(
            entry: holiday, lastDay: nil, today: today, calendar: calendar
        ))
        #expect(!AlarmSkipLogic.shouldReconcileOnStop(
            entry: holiday, lastDay: "2026-11-12", today: today, calendar: calendar
        ))

        var plain = repeating([2])
        #expect(!AlarmSkipLogic.shouldReconcileOnStop(
            entry: plain, lastDay: nil, today: today, calendar: calendar
        ))
    }

    /// 平日（月〜金）＋祝日スキップのアラーム1本で、70日に登録される最大件数。
    /// 2026〜2028 の全日を開始日として計算する（レビューで数字を報告するため）。
    @Test
    func maxCoverageForWeekdayAlarmWithHolidays() {
        var maxCount = 0
        var maxDay: Date?
        var day = date(2026, 1, 1)
        let end = date(2028, 12, 31)
        while day <= end {
            var entry = repeating([2, 3, 4, 5, 6])
            entry.skipsHolidays = true
            let count = 1 + AlarmSkipLogic.coverageOccurrences(
                for: entry, after: day, calendar: calendar
            ).count
            if count > maxCount {
                maxCount = count
                maxDay = day
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        #expect(maxCount == 38, "measured max: \(maxCount) on \(String(describing: maxDay))")
        #expect(maxCount <= AlarmSkipLogic.maxTotalCoverage)
    }
}

/// 1回だけのアラームを休ませたときの保存と取り消し（#197 レビュー）。
@MainActor
extension AlarmSkipServiceTests {

    @Test
    func skipOneTime_disablesItAndUndoRestores() async {
        let original = AlarmStore.shared.alarms
        defer { AlarmStore.shared.replaceAll(original) }

        let entry = AlarmEntry(hour: 7, minute: 0, label: "one-time")
        AlarmStore.shared.replaceAll([entry])
        let occurrence = try? #require(AlarmSkipLogic.oneTimeOccurrenceKey(
            for: entry,
            after: Date()
        ))
        guard let occurrence, let date = AlarmSkipLogic.date(fromKey: occurrence) else {
            Issue.record("one-time occurrence should exist")
            return
        }

        AlarmSkipService.skipDay(date, entries: [entry])
        let saved = AlarmStore.shared.alarms.first
        #expect(saved?.isEnabled == false)
        #expect(saved?.skipDates == [])
        #expect(saved?.skipDisabledDate == occurrence)

        AlarmSkipService.undo(dateKey: occurrence)
        #expect(AlarmStore.shared.alarms.first?.isEnabled == true)
        #expect(AlarmStore.shared.alarms.first?.skipDisabledDate == nil)

        await AlarmScheduler.shared.waitForPendingSync()
    }
}

/// 全体の休み（#197 画面作り直し）。
extension AlarmSkipLogicTests {

    @Test
    func presetIntervalsEndAfterTheExpectedDays() {
        let now = date(2026, 11, 13, 12)
        #expect(AlarmSkipLogic.presetInterval(.hours24, from: now, calendar: calendar)?.end
            == date(2026, 11, 14, 12))
        #expect(AlarmSkipLogic.presetInterval(.days3, from: now, calendar: calendar)?.end
            == date(2026, 11, 16, 12))
        #expect(AlarmSkipLogic.presetInterval(.days7, from: now, calendar: calendar)?.end
            == date(2026, 11, 20, 12))
        #expect(AlarmSkipLogic.presetInterval(.custom, from: now, calendar: calendar) == nil)
    }

    @Test
    func customIntervalIsCappedAtEightWeeks() {
        let now = date(2026, 11, 13, 12)
        let last = calendar.date(byAdding: .day, value: 56, to: now)!
        let tooLate = calendar.date(byAdding: .day, value: 57, to: now)!

        #expect(AlarmSkipLogic.customInterval(
            startDay: now, endDay: last, now: now, calendar: calendar
        ) != nil)
        #expect(AlarmSkipLogic.customInterval(
            startDay: now, endDay: tooLate, now: now, calendar: calendar
        ) == nil)
        #expect(AlarmSkipLogic.customInterval(
            startDay: tooLate, endDay: tooLate, now: now, calendar: calendar
        ) == nil)
        // 終了日はその日の終わりまで
        let interval = AlarmSkipLogic.customInterval(
            startDay: now, endDay: last, now: now, calendar: calendar
        )
        #expect(interval?.end == calendar.date(
            byAdding: .second,
            value: -1,
            to: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last))!
        ))
    }

    @Test
    func globalSkipOnlyAffectsTheSavedEntryIDs() {
        let entry = repeating([1, 2, 3, 4, 5, 6, 7])
        let other = repeating([1, 2, 3, 4, 5, 6, 7])
        let now = date(2026, 11, 13, 12)
        let skip = GlobalSkip(
            start: now,
            end: calendar.date(byAdding: .day, value: 1, to: now)!,
            entryIDs: [entry.id]
        )
        let tomorrow = date(2026, 11, 14, 7)

        #expect(AlarmSkipLogic.isSkipped(
            tomorrow, entry: entry, calendar: calendar, globalSkip: skip
        ))
        #expect(!AlarmSkipLogic.isSkipped(
            tomorrow, entry: other, calendar: calendar, globalSkip: skip
        ))
    }

    @Test
    func globalSkipLeavesTheOccurrenceAfterTheEnd() {
        let entry = AlarmEntry(hour: 23, minute: 0, repeatWeekdays: [1, 2, 3, 4, 5, 6, 7])
        let now = date(2026, 11, 13, 22)
        let end = calendar.date(byAdding: .minute, value: 40, to: date(2026, 11, 14, 22))!
        let skip = GlobalSkip(start: now, end: end, entryIDs: [entry.id])

        #expect(AlarmSkipLogic.isSkipped(
            date(2026, 11, 13), entry: entry, calendar: calendar, globalSkip: skip
        ))
        #expect(!AlarmSkipLogic.isSkipped(
            date(2026, 11, 14), entry: entry, calendar: calendar, globalSkip: skip
        ))
        #expect(AlarmSkipLogic.nextFireDate(
            for: entry, after: now, calendar: calendar, globalSkip: skip
        ) == date(2026, 11, 14, 23))
    }

    @Test
    func occurrenceCountMatchesThePresetWindow() {
        let entry = AlarmEntry(hour: 6, minute: 0, repeatWeekdays: [1, 2, 3, 4, 5, 6, 7])
        let now = date(2026, 11, 13, 12)

        for (preset, expected) in [
            (AlarmSkipLogic.GlobalSkipPreset.hours24, 1),
            (.days3, 3),
            (.days7, 7)
        ] {
            let interval = AlarmSkipLogic.presetInterval(
                preset, from: now, calendar: calendar
            )!
            #expect(AlarmSkipLogic.occurrenceCount(
                entries: [entry], in: interval, calendar: calendar
            ) == expected)
        }
    }

    @Test
    func swipeWordingUsesTheDate() {
        let text = AlarmSkipFormat.day(
            date(2026, 11, 14),
            locale: Locale(identifier: "ja_JP")
        )
        #expect(text.contains("11"))
        #expect(text.contains("14"))
        #expect(!text.contains("次"))
        #expect(!text.contains("明日"))
    }

    @Test
    func oneTimeAlarmCountsOnceEvenInALongBreak() {
        let calendar = Calendar.current
        let hour = (calendar.component(.hour, from: Date()) + 2) % 24
        let oneTime = AlarmEntry(hour: hour, minute: 0, repeatWeekdays: [])
        let now = Date()
        let interval = AlarmSkipLogic.presetInterval(
            .days7,
            from: now,
            calendar: calendar
        )!
        #expect(AlarmSkipLogic.occurrenceCount(
            entries: [oneTime],
            in: interval,
            calendar: calendar
        ) == 1)

        let skip = GlobalSkip(
            start: interval.start,
            end: interval.end,
            entryIDs: [oneTime.id]
        )
        let keys = AlarmSkipLogic.globalSkipKeys(
            for: oneTime,
            from: now,
            days: 7,
            globalSkip: skip,
            calendar: calendar
        )
        #expect(keys.count == 1)
        if let key = keys.first,
           let date = AlarmSkipLogic.date(fromKey: key, calendar: calendar) {
            #expect(AlarmSkipLogic.isSkipped(
                date,
                entry: oneTime,
                calendar: calendar,
                globalSkip: skip
            ))
        } else {
            Issue.record("one-time global skip key should exist")
        }
    }

    @Test
    func globalSkipAlarmCountIncludesDisabledOneTimeAlarms() {
        let entry = AlarmEntry(hour: 7, minute: 0, repeatWeekdays: [])
        var disabled = entry
        disabled.isEnabled = false
        disabled.skipDisabledDate = "2026-11-14"
        let now = date(2026, 11, 13, 12)
        let skip = GlobalSkip(
            start: now,
            end: calendar.date(byAdding: .day, value: 1, to: now)!,
            entryIDs: [entry.id],
            disabledOneTimeIDs: [entry.id]
        )
        #expect(AlarmSkipLogic.globalSkipAlarmCount(
            skip: skip, entries: [disabled]
        ) == 1)
    }

    @Test
    func globalSkipAlarmCountDoesNotCountOccurrences() {
        let entry = repeating([1, 2, 3, 4, 5, 6, 7])
        let now = date(2026, 11, 13, 12)
        let skip = GlobalSkip(
            start: now,
            end: calendar.date(byAdding: .day, value: 7, to: now)!,
            entryIDs: [entry.id]
        )
        // 7日間で7回鳴っても、一覧上部はアラーム1本。
        #expect(AlarmSkipLogic.globalSkipAlarmCount(skip: skip, entries: [entry]) == 1)
    }

    @Test
    func globalSkipRowEndOnlyForIncludedEnabledAlarms() {
        let included = repeating([1, 2, 3, 4, 5, 6, 7])
        let notIncluded = repeating([1, 2, 3, 4, 5, 6, 7])
        var oneTimeDisabled = AlarmEntry(hour: 7, minute: 0, repeatWeekdays: [])
        oneTimeDisabled.isEnabled = false
        oneTimeDisabled.skipDisabledDate = "2026-11-14"
        let now = date(2026, 11, 13, 12)
        let end = calendar.date(byAdding: .day, value: 1, to: now)!
        let skip = GlobalSkip(
            start: now,
            end: end,
            entryIDs: [included.id, oneTimeDisabled.id],
            disabledOneTimeIDs: [oneTimeDisabled.id]
        )

        #expect(AlarmSkipLogic.globalSkipRowEnd(
            for: included, now: now, globalSkip: skip
        ) == end)
        #expect(AlarmSkipLogic.globalSkipRowEnd(
            for: notIncluded, now: now, globalSkip: skip
        ) == nil)
        #expect(AlarmSkipLogic.globalSkipRowEnd(
            for: oneTimeDisabled, now: now, globalSkip: skip
        ) == nil)
        #expect(AlarmSkipLogic.globalSkipRowEnd(
            for: included,
            now: end.addingTimeInterval(1),
            globalSkip: skip
        ) == nil)
    }
}

/// 全体の休みの取り消しは、個別の休みを消さない（#197 画面作り直し）。
@MainActor
extension AlarmSkipServiceTests {

    @Test
    func undoAllKeepsIndividualSkipsAndRestoresOneTimeAlarms() async {
        let original = AlarmStore.shared.alarms
        let originalSkip = AppGroup.globalSkip
        defer {
            AlarmStore.shared.replaceAll(original)
            AppGroup.globalSkip = originalSkip
        }
        AppGroup.globalSkip = nil

        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        let key = AlarmSkipLogic.dateKey(tomorrow, calendar: calendar)

        var repeating = AlarmEntry(
            hour: 7,
            minute: 0,
            label: "global-test",
            repeatWeekdays: [1, 2, 3, 4, 5, 6, 7]
        )
        repeating.skipDates = [key]
        let oneTime = AlarmEntry(hour: 8, minute: 0, label: "global-one-time")
        AlarmStore.shared.replaceAll([repeating, oneTime])

        let count = AlarmSkipService.skipAll(preset: .hours24)
        #expect(count == 2)
        #expect(AppGroup.globalSkip?.entryIDs.count == 2)
        #expect(AppGroup.globalSkip?.disabledOneTimeIDs.contains(oneTime.id) == true)
        #expect(AlarmStore.shared.alarms.first { $0.id == oneTime.id }?.isEnabled == false)

        AlarmSkipService.undoAll()
        #expect(AppGroup.globalSkip == nil)
        let restored = AlarmStore.shared.alarms
        #expect(restored.first { $0.id == repeating.id }?.skipDates == [key])
        #expect(restored.first { $0.id == oneTime.id }?.isEnabled == true)
        #expect(restored.first { $0.id == oneTime.id }?.skipDisabledDate == nil)

        await AlarmScheduler.shared.waitForPendingSync()
    }
}

/// 年をまたぐ日付の表示（#197 実機レビュー）。
extension AlarmSkipLogicTests {

    @Test
    func dateLabelsAddTheYearOnlyOutsideTheCurrentYear() {
        let ja = Locale(identifier: "ja_JP")
        let thisYear = date(2026, 11, 1)

        #expect(AlarmSkipFormat.day(
            date(2026, 11, 14), locale: ja, now: thisYear
        ) == "11/14（土）")
        #expect(AlarmSkipFormat.day(
            date(2026, 12, 31), locale: ja, now: thisYear
        ) == "12/31（木）")
        #expect(AlarmSkipFormat.day(
            date(2027, 1, 1), locale: ja, now: thisYear
        ) == "2027/1/1（金）")
        #expect(AlarmSkipFormat.day(
            date(2027, 1, 1), locale: ja, now: date(2027, 1, 1)
        ) == "1/1（金）")
        // 12/31 → 1/1 をまたぐ基準日でも、翌年側だけ年が付く
        #expect(AlarmSkipFormat.day(
            date(2026, 12, 31), locale: ja, now: date(2026, 12, 31)
        ) == "12/31（木）")
        #expect(AlarmSkipFormat.day(
            date(2027, 1, 1), locale: ja, now: date(2026, 12, 31)
        ) == "2027/1/1（金）")

        let en = Locale(identifier: "en_US")
        #expect(AlarmSkipFormat.day(
            date(2027, 1, 1), locale: en, now: thisYear
        ).contains("2027"))
        #expect(AlarmSkipFormat.year(2027, locale: ja) == "2027年")
    }
}

/// 一覧右上・スワイプ・長押しで使うアイコン（#197 実機レビュー：禁止マーク案）。
@MainActor
struct AlarmOffIconTests {

    @Test
    func rendersForMenuAtFixedSize() throws {
        let image = try #require(AlarmOffIconRenderer.image(pointSize: 20))
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }

    @Test
    func reusesTheRenderedImageForTheSameSize() throws {
        let first = try #require(AlarmOffIconRenderer.image(pointSize: 22))
        let second = try #require(AlarmOffIconRenderer.image(pointSize: 22))
        #expect(first === second)
    }

    @Test
    func badgeSitsAtTheBottomRightAndStaysSmallerThanTheClock() {
        #expect(AlarmOffIcon.badgeDiameterRatio < 1)
        #expect(AlarmOffIcon.badgeDiameterRatio > 0.4)
        #expect(AlarmOffIcon.badgeCenterInsetRatio < 0.5)
        #expect(AlarmOffIcon.badgeGapRatio > 0)
    }
}
