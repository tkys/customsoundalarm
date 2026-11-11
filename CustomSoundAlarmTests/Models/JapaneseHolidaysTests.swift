import Testing
import Foundation
@testable import CustomSoundAlarm

/// 祝日データ（2026〜2028・振替休日・国民の休日）の検証（#197）。
struct JapaneseHolidaysTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    @Test
    func coversEveryYearInTheTable() {
        #expect(AlarmSkipLogic.holidayYearsAreComplete())
        let years = Set(JapaneseHolidays.all.compactMap { Int($0.dateKey.prefix(4)) })
        #expect(years == [2026, 2027, 2028])
    }

    @Test
    func datesAreUniqueAndSortedWithinEachYear() {
        #expect(Set(JapaneseHolidays.all.map(\.dateKey)).count == JapaneseHolidays.all.count)
        for year in JapaneseHolidays.firstYear...JapaneseHolidays.lastYear {
            let keys = JapaneseHolidays.all
                .filter { $0.dateKey.hasPrefix("\(year)-") }
                .map(\.dateKey)
            #expect(keys == keys.sorted())
            #expect(!keys.isEmpty)
        }
    }

    @Test
    func substituteHolidayIsIncluded() {
        // 2026-05-03（日）の振替休日
        #expect(JapaneseHolidays.holiday(on: "2026-05-06")?.name == "振替休日")
        // 2027-03-21（日）の振替休日
        #expect(JapaneseHolidays.holiday(on: "2027-03-22")?.name == "振替休日")
    }

    @Test
    func citizensHolidayIsIncluded() {
        // 2026-09-21（敬老の日）と 2026-09-23（秋分の日）の間
        #expect(JapaneseHolidays.holiday(on: "2026-09-22")?.name == "国民の休日")
    }

    @Test
    func substituteIsNotAddedForSaturday() {
        // 2028-04-29 は土曜。振替休日は日曜のときだけ。
        #expect(JapaneseHolidays.holiday(on: "2028-04-30") == nil)
    }

    @Test
    func isHolidayUsesTheLocalDate() throws {
        let date = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 23, hour: 12
        )))
        #expect(JapaneseHolidays.isHoliday(date, calendar: calendar))
    }

    @Test
    func upcomingReturnsHolidaysInRange() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let holidays = JapaneseHolidays.upcoming(from: start, days: 30, calendar: calendar)
        #expect(holidays.map(\.dateKey) == ["2026-11-03", "2026-11-23"])
    }

    /// 最終年（2028）の1年前（2027-01-01）から失敗させ、データ更新に気づけるようにする（#197）。
    @Test
    func holidayDataIsStillFresh() {
        #expect(
            !JapaneseHolidays.needsUpdate(),
            "祝日データ（2026〜2028）の更新時期です。内閣府の一覧を追加してください"
        )
    }

    @Test
    func updateWarningStartsOneYearBeforeTheLastYear() {
        let before = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31))!
        let warn = calendar.date(from: DateComponents(year: 2027, month: 1, day: 1))!
        #expect(!JapaneseHolidays.needsUpdate(now: before, calendar: calendar))
        #expect(JapaneseHolidays.needsUpdate(now: warn, calendar: calendar))
    }
}
