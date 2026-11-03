import Foundation
import Testing
@testable import CustomSoundAlarm

struct AlarmSyncSafetyTests {

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int, _ minute: Int, _ second: Int = 0
    ) -> Date {
        calendar().date(from: DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second
        ))!
    }

    @Test
    func currentMinute_isDeferred() {
        let entry = AlarmEntry(hour: 6, minute: 25, repeatWeekdays: [4])
        #expect(AlarmSyncSafety.shouldDeferReschedule(
            for: entry,
            now: date(2026, 11, 4, 6, 25, 30),
            calendar: calendar()
        ))
    }

    @Test
    func previousMinute_isDeferred() {
        let entry = AlarmEntry(hour: 6, minute: 25, repeatWeekdays: [4])
        #expect(AlarmSyncSafety.shouldDeferReschedule(
            for: entry,
            now: date(2026, 11, 4, 6, 26, 30),
            calendar: calendar()
        ))
    }

    @Test
    func twoMinutesLater_isNotDeferred() {
        let entry = AlarmEntry(hour: 6, minute: 25, repeatWeekdays: [4])
        #expect(!AlarmSyncSafety.shouldDeferReschedule(
            for: entry,
            now: date(2026, 11, 4, 6, 27, 0),
            calendar: calendar()
        ))
    }

    @Test
    func oneTimeAlarm_isNotDeferred() {
        let entry = AlarmEntry(hour: 6, minute: 25)
        #expect(!AlarmSyncSafety.shouldDeferReschedule(
            for: entry,
            now: date(2026, 11, 4, 6, 25, 30),
            calendar: calendar()
        ))
    }

    @Test
    func nonRepeatingDay_isNotDeferred() {
        // 2026-11-04 は水曜（weekday 4）
        let entry = AlarmEntry(hour: 6, minute: 25, repeatWeekdays: [2])
        #expect(!AlarmSyncSafety.shouldDeferReschedule(
            for: entry,
            now: date(2026, 11, 4, 6, 26, 30),
            calendar: calendar()
        ))
    }

    @Test
    func editedEntry_isNotDeferred() {
        let entry = AlarmEntry(hour: 6, minute: 25, repeatWeekdays: [4])
        #expect(!AlarmSyncSafety.shouldDeferReschedule(
            for: entry,
            editedEntryIDs: [entry.id],
            now: date(2026, 11, 4, 6, 26, 30),
            calendar: calendar()
        ))
    }

    @Test
    func previousMinuteAcrossMidnight_isDeferred() {
        // 2026-11-09 は月曜 00:00。日曜 23:59 の繰り返しを直前の分として扱う。
        let entry = AlarmEntry(hour: 23, minute: 59, repeatWeekdays: [1])
        #expect(AlarmSyncSafety.shouldDeferReschedule(
            for: entry,
            now: date(2026, 11, 9, 0, 0, 30),
            calendar: calendar()
        ))
    }
}

struct AlarmSyncTriggerLogicTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func recentStopIntent_isIntent() {
        #expect(AlarmSyncTriggerLogic.launchTrigger(
            now: now,
            lastStopIntentAt: now.addingTimeInterval(-5)
        ) == .intent)
    }

    @Test
    func oldStopIntent_isLaunch() {
        #expect(AlarmSyncTriggerLogic.launchTrigger(
            now: now,
            lastStopIntentAt: now.addingTimeInterval(-31)
        ) == .launch)
    }

    @Test
    func noStopIntent_isLaunch() {
        #expect(AlarmSyncTriggerLogic.launchTrigger(
            now: now,
            lastStopIntentAt: nil
        ) == .launch)
    }

    @Test
    func futureStopIntent_isLaunch() {
        #expect(AlarmSyncTriggerLogic.launchTrigger(
            now: now,
            lastStopIntentAt: now.addingTimeInterval(5)
        ) == .launch)
    }
}

struct AlarmSyncLogTests {

    private func entry(_ index: Int) -> AlarmSyncLogEntry {
        AlarmSyncLogEntry(
            trigger: .foreground,
            timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
            rescheduledCount: index,
            deferredCount: 0,
            changedCount: index,
            missingCount: 0,
            forcedCount: 0
        )
    }

    @Test
    func appending_keepsOnlyTheNewestFifty() {
        var log: [AlarmSyncLogEntry] = []
        for index in 0..<60 {
            log = AlarmSyncLog.appending(entry(index), to: log)
        }

        #expect(log.count == AlarmSyncLog.maxEntries)
        #expect(log.first?.rescheduledCount == 10)
        #expect(log.last?.rescheduledCount == 59)
    }

    @Test
    func logEntry_roundTrips() throws {
        let original = AlarmSyncLogEntry(
            trigger: .intent,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            rescheduledCount: 3,
            deferredCount: 1,
            changedCount: 2,
            missingCount: 1,
            forcedCount: 0
        )
        let decoded = try JSONDecoder().decode(
            AlarmSyncLogEntry.self,
            from: JSONEncoder().encode(original)
        )
        #expect(decoded == original)
    }
}
