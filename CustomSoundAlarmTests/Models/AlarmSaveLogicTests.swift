import Testing
import Foundation
@testable import CustomSoundAlarm

struct AlarmSaveLogicTests {

    @Test
    func newEntry_isAlwaysEnabled() {
        let entry = AlarmSaveLogic.newEntry(
            hour: 7,
            minute: 30,
            label: "Morning",
            repeatWeekdays: [2, 3],
            soundFileName: "a.caf",
            snoozeMinutes: 5,
            backupMinutes: 15
        )

        #expect(entry.isEnabled)
        #expect(entry.hour == 7)
        #expect(entry.minute == 30)
        #expect(entry.label == "Morning")
        #expect(entry.repeatWeekdays == [2, 3])
        #expect(entry.soundFileName == "a.caf")
        #expect(entry.snoozeMinutes == 5)
        #expect(entry.backupMinutes == 15)
    }

    @Test
    func updatedEntry_forcesEnabled() {
        let existing = AlarmEntry(
            hour: 6,
            minute: 0,
            isEnabled: false,
            label: "Old",
            repeatWeekdays: [1],
            soundFileName: "old.caf",
            snoozeMinutes: 9,
            backupMinutes: nil
        )

        let updated = AlarmSaveLogic.updatedEntry(
            from: existing,
            hour: 8,
            minute: 15,
            label: "New",
            repeatWeekdays: [2, 4],
            soundFileName: "new.caf",
            snoozeMinutes: 10,
            backupMinutes: 20
        )

        #expect(updated.isEnabled, "編集して保存したらオン")
        #expect(updated.id == existing.id)
        #expect(updated.hour == 8)
        #expect(updated.minute == 15)
        #expect(updated.label == "New")
        #expect(updated.repeatWeekdays == [2, 4])
        #expect(updated.soundFileName == "new.caf")
        #expect(updated.snoozeMinutes == 10)
        #expect(updated.backupMinutes == 20)
    }

    @Test
    func newEntry_carriesPlaylistFields() {
        let playlistID = UUID()
        let entry = AlarmSaveLogic.newEntry(
            hour: 7,
            minute: 0,
            label: "Playlist",
            repeatWeekdays: [],
            soundFileName: "",
            snoozeMinutes: 9,
            backupMinutes: nil,
            playlistID: playlistID,
            fadeIn: .thirty
        )

        #expect(entry.playlistID == playlistID)
        #expect(entry.fadeIn == .thirty)
        #expect(entry.usesPlaylistFeatures)
    }

    @Test
    func updatedEntry_carriesPlaylistFields() {
        let existing = AlarmEntry()
        let playlistID = UUID()
        let updated = AlarmSaveLogic.updatedEntry(
            from: existing,
            hour: 8,
            minute: 15,
            label: "New",
            repeatWeekdays: [],
            soundFileName: "",
            snoozeMinutes: 9,
            backupMinutes: nil,
            playlistID: playlistID,
            fadeIn: .fifteen
        )

        #expect(updated.playlistID == playlistID)
        #expect(updated.fadeIn == .fifteen)
    }

    @Test
    func updatedEntry_keepsSkipDatesWhenOnlyTheTimeChanges() {
        let calendar = Calendar.current
        let monday = calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 16)
        )!
        let key = AlarmSkipLogic.dateKey(monday, calendar: calendar)
        var existing = AlarmEntry(
            hour: 7,
            minute: 0,
            repeatWeekdays: [2],
            skipDates: [key]
        )

        let updated = AlarmSaveLogic.updatedEntry(
            from: existing,
            hour: 8,
            minute: 30,
            label: "New",
            repeatWeekdays: [2],
            soundFileName: "",
            snoozeMinutes: 9,
            backupMinutes: nil,
            skipDates: existing.skipDates
        )

        #expect(updated.skipDates == [key])
        existing.hour = 8
        #expect(updated.hour == 8)
    }

    @Test
    func updatedEntry_dropsSkipDatesThatDoNotMatchTheNewWeekdays() {
        let calendar = Calendar.current
        let monday = calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 16)
        )!
        let tuesday = calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 17)
        )!
        let mondayKey = AlarmSkipLogic.dateKey(monday, calendar: calendar)
        let tuesdayKey = AlarmSkipLogic.dateKey(tuesday, calendar: calendar)
        let existing = AlarmEntry(
            hour: 7,
            minute: 0,
            repeatWeekdays: [2, 3],
            skipDates: [mondayKey, tuesdayKey]
        )

        let onlyMonday = AlarmSaveLogic.updatedEntry(
            from: existing,
            hour: 7,
            minute: 0,
            label: "New",
            repeatWeekdays: [2],
            soundFileName: "",
            snoozeMinutes: 9,
            backupMinutes: nil,
            skipDates: existing.skipDates
        )
        #expect(onlyMonday.skipDates == [mondayKey])

        let none = AlarmSaveLogic.updatedEntry(
            from: existing,
            hour: 7,
            minute: 0,
            label: "New",
            repeatWeekdays: [5],
            soundFileName: "",
            snoozeMinutes: 9,
            backupMinutes: nil,
            skipDates: existing.skipDates
        )
        #expect(none.skipDates.isEmpty)
    }
}

/// 繰り返し行の要約文言（#197 レビュー）。
struct RepeatSummaryLogicTests {

    private func japaneseStrings() throws -> RepeatSummaryStrings {
        let path = try #require(
            Bundle.main.path(forResource: "ja", ofType: "lproj"),
            "ja.lproj"
        )
        let bundle = try #require(Bundle(path: path))
        return RepeatSummaryStrings(bundle: bundle, language: "ja")
    }

    @Test
    func noSkipsKeepsTheCurrentText() throws {
        let strings = try japaneseStrings()
        #expect(RepeatSummaryLogic.text(
            weekdays: [2, 3, 4, 5, 6],
            skipsHolidays: false,
            skipDateCount: 0,
            strings: strings
        ) == "平日")
        #expect(RepeatSummaryLogic.text(
            weekdays: [1, 2, 3, 4, 5, 6, 7],
            skipsHolidays: false,
            skipDateCount: 0,
            strings: strings
        ) == "毎日")
        #expect(RepeatSummaryLogic.text(
            weekdays: [2, 4, 6],
            skipsHolidays: false,
            skipDateCount: 0,
            strings: strings
        ) == "月 水 金")
        #expect(RepeatSummaryLogic.text(
            weekdays: [],
            skipsHolidays: true,
            skipDateCount: 2,
            strings: strings
        ) == "しない")
    }

    @Test
    func holidayAndDateSkipsAreShownAsResults() throws {
        let strings = try japaneseStrings()
        #expect(RepeatSummaryLogic.text(
            weekdays: [2, 3, 4, 5, 6],
            skipsHolidays: true,
            skipDateCount: 0,
            strings: strings
        ) == "平日・祝日を除く")
        #expect(RepeatSummaryLogic.text(
            weekdays: [1, 2, 3, 4, 5, 6, 7],
            skipsHolidays: false,
            skipDateCount: 2,
            strings: strings
        ) == "毎日・2日を除く")
        #expect(RepeatSummaryLogic.text(
            weekdays: [1, 2, 3, 4, 5, 6, 7],
            skipsHolidays: true,
            skipDateCount: 2,
            strings: strings
        ) == "毎日・祝日と2日を除く")
    }
}

/// 「この先、鳴らない日」の結果リスト（#197 実機レビュー）。
struct SkipResultLogicTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.locale = Locale(identifier: "ja_JP")
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day
        ))!
    }

    private let holidays = [
        JapaneseHoliday(dateKey: "2026-11-23", name: "勤労感謝の日"),
        JapaneseHoliday(dateKey: "2027-01-01", name: "元日"),
        JapaneseHoliday(dateKey: "2027-01-11", name: "成人の日"),
    ]

    private func sections(
        now: Date,
        skipsHolidays: Bool = true,
        skipDates: Set<String> = [],
        overrides: Set<String> = [],
        isJapan: Bool = true,
        horizonDays: Int = SkipResultLogic.initialDays
    ) -> [SkipResultYear] {
        SkipResultLogic.sections(
            weekdays: [1, 2, 3, 4, 5, 6, 7],
            skipsHolidays: skipsHolidays,
            skipDates: skipDates,
            holidayRingOverrides: overrides,
            isJapan: isJapan,
            now: now,
            horizonDays: horizonDays,
            holidays: holidays,
            calendar: calendar
        )
    }

    @Test
    func sameDayPickedWinsOverHoliday() throws {
        let result = sections(
            now: date(2026, 11, 14),
            skipDates: ["2026-11-23"]
        )
        let days = result.flatMap(\.days)
        let sameDay = days.filter { $0.dateKey == "2026-11-23" }
        #expect(sameDay.count == 1)
        let day = try #require(sameDay.first)
        #expect(day.kind == .picked)
        #expect(day.isSkipped)
    }

    @Test
    func holidayOverrideRings() throws {
        let result = sections(
            now: date(2026, 11, 14),
            overrides: ["2026-11-23"]
        )
        let day = try #require(
            result.flatMap(\.days).first { $0.dateKey == "2026-11-23" }
        )
        #expect(day.kind == .holiday(name: "勤労感謝の日"))
        #expect(!day.isSkipped)
    }

    @Test
    func holidayOffShowsOnlyPickedDays() {
        let result = sections(
            now: date(2026, 11, 14),
            skipsHolidays: false,
            skipDates: ["2026-11-23"],
            horizonDays: SkipResultLogic.extendedDays
        )
        let days = result.flatMap(\.days)
        #expect(days.count == 1)
        #expect(days.first?.kind == .picked)
        #expect(days.first?.dateKey == "2026-11-23")
    }

    @Test
    func horizonStartsAtEightWeeksAndExtendsToOneYear() {
        // 2026-11-14 の56日後は 2027-01-09。1/11 は8週間の外、1年の中。
        let now = date(2026, 11, 14)
        let initial = sections(now: now, horizonDays: SkipResultLogic.initialDays)
        let extended = sections(now: now, horizonDays: SkipResultLogic.extendedDays)
        #expect(!initial.flatMap(\.days).contains { $0.dateKey == "2027-01-11" })
        #expect(extended.flatMap(\.days).contains { $0.dateKey == "2027-01-11" })
    }

    @Test
    func sectionsAreSortedByYearAndDate() {
        let result = sections(
            now: date(2026, 11, 14),
            horizonDays: SkipResultLogic.extendedDays
        )
        #expect(result.map(\.year) == [2026, 2027])
        let days = result.flatMap(\.days)
        #expect(days.map(\.date) == days.map(\.date).sorted())
        #expect(days.first?.dateKey == "2026-11-23")
        #expect(days.last?.dateKey == "2027-01-11")
    }

    @Test
    func nonJapanHasNoHolidayRows() {
        let result = sections(
            now: date(2026, 11, 14),
            skipDates: ["2026-11-23"],
            isJapan: false
        )
        let days = result.flatMap(\.days)
        #expect(days.count == 1)
        #expect(days.first?.kind == .picked)
    }

    @Test
    func holidayOnAnUnselectedWeekdayIsExcluded() {
        // 水曜だけ選ぶと、月曜・金曜の祝日は出ない。
        let result = SkipResultLogic.sections(
            weekdays: [4],
            skipsHolidays: true,
            skipDates: [],
            holidayRingOverrides: [],
            isJapan: true,
            now: date(2026, 11, 14),
            horizonDays: SkipResultLogic.extendedDays,
            holidays: holidays,
            calendar: calendar
        )
        #expect(result.isEmpty)
    }
}
