import Testing
import Foundation
@testable import CustomSoundAlarm

/// 次に鳴るまでの1文（#289）の計算を検証する。
struct NextRingAnnouncementTests {

    private let timeZone = TimeZone(identifier: "Asia/Tokyo")!

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int, _ minute: Int, _ second: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        ))!
    }

    private func entry(
        hour: Int,
        minute: Int,
        repeatWeekdays: [Int] = [],
        isEnabled: Bool = true,
        label: String = "アラーム",
        soundFileName: String = "",
        skipDates: [String] = []
    ) -> AlarmEntry {
        AlarmEntry(
            hour: hour,
            minute: minute,
            isEnabled: isEnabled,
            label: label,
            repeatWeekdays: repeatWeekdays,
            soundFileName: soundFileName,
            skipDates: skipDates
        )
    }

    // MARK: - 24時間未満

    /// 0分台（1分未満）は「0分後」にせず、1分後に切り上げる。
    @Test
    func underOneMinuteRoundsUpToOneMinute() {
        let now = date(2026, 11, 24, 6, 59, 30)
        let alarm = entry(hour: 7, minute: 0)

        #expect(
            NextRingAnnouncement.kind(for: alarm, now: now, calendar: calendar)
                == .minutes(1)
        )
    }

    /// 59分ちょうど（秒を含む）は59分のまま。
    @Test
    func fiftyNineMinutesStaysFiftyNine() {
        let now = date(2026, 11, 24, 6, 0, 30)
        let alarm = entry(hour: 7, minute: 0)

        #expect(
            NextRingAnnouncement.kind(for: alarm, now: now, calendar: calendar)
                == .minutes(59)
        )
    }

    /// 23時間59分は24時間未満なので、残り時間で出す。
    @Test
    func twentyThreeHoursFiftyNineMinutesStaysDuration() {
        let now = date(2026, 11, 24, 7, 0, 30)
        let fire = date(2026, 11, 25, 7, 0)

        #expect(
            NextRingAnnouncement.kind(fireDate: fire, now: now)
                == .minutes(23 * 60 + 59)
        )
    }

    /// 日をまたぐ20分（23:50 → 翌0:10）は、日付ではなく残り時間で出す。
    @Test
    func crossingMidnightUsesMinutes() {
        let now = date(2026, 11, 24, 23, 50)
        let alarm = entry(hour: 0, minute: 10)

        #expect(
            NextRingAnnouncement.kind(for: alarm, now: now, calendar: calendar)
                == .minutes(20)
        )
    }

    // MARK: - 24時間以上

    /// ちょうど24時間は「24時間以上」なので、曜日と時刻で出す。
    @Test
    func exactlyTwentyFourHoursUsesWeekday() {
        let now = date(2026, 11, 24, 7, 0)
        let fire = now.addingTimeInterval(NextRingAnnouncement.oneDay)

        #expect(
            NextRingAnnouncement.kind(fireDate: fire, now: now)
                == .weekday(fire)
        )
    }

    /// 24時間ちょうどの繰り返し（火7:00 → 水7:00）も曜日と時刻で出す。
    @Test
    func exactlyTwentyFourHoursForRepeatingAlarm() {
        let now = date(2026, 11, 24, 7, 0)
        let alarm = entry(hour: 7, minute: 0, repeatWeekdays: [4])

        let kind = NextRingAnnouncement.kind(
            for: alarm,
            now: now,
            calendar: calendar
        )
        let expectedFire = date(2026, 11, 25, 7, 0)
        #expect(kind == .weekday(expectedFire))
    }

    /// 曜日指定の繰り返しは、既存の nextFireDate（次の月曜）をそのまま使う。
    @Test
    func weekdayUsesExistingNextFireDate() {
        // 2026-11-25 は水曜。次の月曜は 2026-11-30。
        let now = date(2026, 11, 25, 8, 0)
        let alarm = entry(hour: 7, minute: 30, repeatWeekdays: [2])
        let expectedFire = date(2026, 11, 30, 7, 30)

        #expect(
            alarm.nextFireDate(from: now, calendar: calendar) == expectedFire
        )
        #expect(
            NextRingAnnouncement.kind(for: alarm, now: now, calendar: calendar)
                == .weekday(expectedFire)
        )
    }

    /// 休む日をまたぐときは、休みを除いた次の日（火曜）で出す。
    @Test
    func skippedDayIsExcludedFromNextFireDate() {
        // 2026-11-29 は日曜。翌日（月曜）を休む。
        let now = date(2026, 11, 29, 8, 0)
        let alarm = entry(
            hour: 7,
            minute: 0,
            repeatWeekdays: [1, 2, 3, 4, 5, 6, 7],
            skipDates: ["2026-11-30"]
        )
        let expectedFire = date(2026, 12, 1, 7, 0)

        #expect(
            alarm.nextFireDate(from: now, calendar: calendar) == expectedFire
        )
        #expect(
            NextRingAnnouncement.kind(for: alarm, now: now, calendar: calendar)
                == .weekday(expectedFire)
        )
    }

    @Test
    func disabledAlarmHasNoAnnouncement() {
        let now = date(2026, 11, 24, 8, 0)
        let alarm = entry(hour: 7, minute: 0, isEnabled: false)

        #expect(
            NextRingAnnouncement.kind(for: alarm, now: now, calendar: calendar)
                == nil
        )
        #expect(
            NextRingAnnouncement.message(for: alarm, now: now, calendar: calendar)
                == nil
        )
    }

    // MARK: - 文言の材料

    @Test
    func durationTextKeepsHoursAndMinutes() {
        let sevenHoursTwentyFive = NextRingAnnouncement.durationText(minutes: 445)
        #expect(sevenHoursTwentyFive.contains("7"))
        #expect(sevenHoursTwentyFive.contains("25"))

        let twentyFive = NextRingAnnouncement.durationText(minutes: 25)
        #expect(twentyFive.contains("25"))
    }

    @Test
    func japaneseWeekdayIsShort() {
        let monday = date(2026, 11, 30, 7, 30)
        let name = NextRingAnnouncement.weekdayText(
            monday,
            locale: Locale(identifier: "ja_JP"),
            calendar: calendar,
            timeZone: timeZone
        )
        #expect(name == "月曜")
    }

    @Test
    func englishWeekdayIsWide() {
        let monday = date(2026, 11, 30, 7, 30)
        let name = NextRingAnnouncement.weekdayText(
            monday,
            locale: Locale(identifier: "en_US"),
            calendar: calendar,
            timeZone: timeZone
        )
        #expect(name == "Monday")
    }

    // MARK: - 出す場面

    @Test
    func newSaveAnnounces() {
        #expect(
            NextRingAnnouncement.shouldAnnounce(
                isNew: true,
                previous: nil,
                updated: entry(hour: 7, minute: 0)
            )
        )
    }

    @Test
    func changingOnlyNameOrSoundDoesNotAnnounce() {
        let previous = entry(
            hour: 7,
            minute: 0,
            label: "前",
            soundFileName: "A.caf"
        )
        let updated = entry(
            hour: 7,
            minute: 0,
            label: "後",
            soundFileName: "B.caf"
        )

        #expect(
            !NextRingAnnouncement.shouldAnnounce(
                isNew: false,
                previous: previous,
                updated: updated
            )
        )
    }

    @Test
    func changingTimeOrRepeatOrRestAnnounces() {
        let base = entry(hour: 7, minute: 0, repeatWeekdays: [2])

        #expect(
            NextRingAnnouncement.shouldAnnounce(
                isNew: false,
                previous: base,
                updated: entry(hour: 7, minute: 30, repeatWeekdays: [2])
            )
        )
        #expect(
            NextRingAnnouncement.shouldAnnounce(
                isNew: false,
                previous: base,
                updated: entry(hour: 7, minute: 0, repeatWeekdays: [3])
            )
        )
        #expect(
            NextRingAnnouncement.shouldAnnounce(
                isNew: false,
                previous: base,
                updated: entry(
                    hour: 7,
                    minute: 0,
                    repeatWeekdays: [2],
                    skipDates: ["2026-12-07"]
                )
            )
        )
    }

    @Test
    func turningOnAnnounces() {
        let previous = entry(hour: 7, minute: 0, isEnabled: false)
        let updated = entry(hour: 7, minute: 0, isEnabled: true)

        #expect(
            NextRingAnnouncement.shouldAnnounce(
                isNew: false,
                previous: previous,
                updated: updated
            )
        )
    }
}
