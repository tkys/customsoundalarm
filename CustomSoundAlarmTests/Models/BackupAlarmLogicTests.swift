import Testing
import Foundation
import AlarmKit
@testable import CustomSoundAlarm

struct BackupAlarmLogicTests {

    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d
        c.hour = h; c.minute = mi; c.second = 0
        return Self.cal.date(from: c)!
    }

    private func next(_ entry: AlarmEntry, after ref: Date, skipping: Bool) -> Date? {
        BackupAlarmLogic.nextBackupDate(
            for: entry,
            after: ref,
            skippingCurrentOccurrence: skipping,
            calendar: Self.cal
        )
    }

    // MARK: - nextBackupDate: 繰り返し

    @Test
    func nextBackupDate_beforePrimary_usesToday() {
        // 毎日 7:00 + 15分
        let entry = AlarmEntry(hour: 7, minute: 0, repeatWeekdays: [1, 2, 3, 4, 5, 6, 7], backupMinutes: 15)
        let ref = date(2024, 1, 15, 6, 0) // 月曜

        #expect(next(entry, after: ref, skipping: false) == date(2024, 1, 15, 7, 15))
    }

    @Test
    func nextBackupDate_duringPrimary_keepsTodayDeadline() {
        // 7:05（本体の鳴動/スヌーズ中）でも今日の 7:15 を維持する
        let entry = AlarmEntry(hour: 7, minute: 0, repeatWeekdays: [2], backupMinutes: 15)
        let ref = date(2024, 1, 15, 7, 5)

        #expect(next(entry, after: ref, skipping: false) == date(2024, 1, 15, 7, 15))
    }

    @Test
    func nextBackupDate_afterDeadline_usesNextOccurrence() {
        let entry = AlarmEntry(hour: 7, minute: 0, repeatWeekdays: [2], backupMinutes: 15)
        let ref = date(2024, 1, 15, 7, 16)

        #expect(next(entry, after: ref, skipping: false) == date(2024, 1, 22, 7, 15))
    }

    @Test
    func nextBackupDate_skippingCurrent_usesNextWeek() {
        let entry = AlarmEntry(hour: 7, minute: 0, repeatWeekdays: [2], backupMinutes: 15)
        let ref = date(2024, 1, 15, 7, 0)

        #expect(next(entry, after: ref, skipping: true) == date(2024, 1, 22, 7, 15))
    }

    @Test
    func nextBackupDate_weeklyOnOtherDay() {
        // 月曜(2) 7:00、日曜に読む
        let entry = AlarmEntry(hour: 7, minute: 0, repeatWeekdays: [2], backupMinutes: 15)
        let ref = date(2024, 1, 14, 12, 0)

        #expect(next(entry, after: ref, skipping: false) == date(2024, 1, 15, 7, 15))
    }

    // MARK: - nextBackupDate: 日付またぎ

    @Test
    func nextBackupDate_crossesMidnight() {
        // 23:50 + 20分 = 翌日 00:10
        let entry = AlarmEntry(hour: 23, minute: 50, repeatWeekdays: [2], backupMinutes: 20)
        let ref = date(2024, 1, 15, 23, 55)

        #expect(next(entry, after: ref, skipping: false) == date(2024, 1, 16, 0, 10))
    }

    @Test
    func nextBackupDate_crossesMidnight_skippingCurrent() {
        let entry = AlarmEntry(hour: 23, minute: 50, repeatWeekdays: [2], backupMinutes: 20)
        let ref = date(2024, 1, 15, 23, 50)

        // 次回の本体は翌週月曜 23:50 → 火曜 00:10
        #expect(next(entry, after: ref, skipping: true) == date(2024, 1, 23, 0, 10))
    }

    @Test
    func nextBackupDate_afterCrossMidnightDeadline() {
        let entry = AlarmEntry(hour: 23, minute: 50, repeatWeekdays: [2], backupMinutes: 20)
        let ref = date(2024, 1, 16, 0, 15)

        // 今回分は過ぎた → 次の月曜 23:50 + 20分
        #expect(next(entry, after: ref, skipping: false) == date(2024, 1, 23, 0, 10))
    }

    // MARK: - nextBackupDate: 一回限り

    @Test
    func nextBackupDate_oneTime_today() {
        let entry = AlarmEntry(hour: 7, minute: 0, repeatWeekdays: [], backupMinutes: 15)
        let ref = date(2024, 1, 15, 6, 0)

        #expect(next(entry, after: ref, skipping: false) == date(2024, 1, 15, 7, 15))
    }

    @Test
    func nextBackupDate_oneTime_skippingReturnsNil() {
        let entry = AlarmEntry(hour: 7, minute: 0, repeatWeekdays: [], backupMinutes: 15)
        let ref = date(2024, 1, 15, 7, 0)

        #expect(next(entry, after: ref, skipping: true) == nil, "一回限りは次回分を作らない")
    }

    @Test
    func nextBackupDate_oneTime_createdAfterTodaysTime() {
        let entry = AlarmEntry(hour: 7, minute: 0, repeatWeekdays: [], backupMinutes: 15)
        let ref = date(2024, 1, 15, 8, 0)

        #expect(next(entry, after: ref, skipping: false) == date(2024, 1, 16, 7, 15))
    }

    @Test
    func nextBackupDate_nilWhenDisabledOrOff() {
        let ref = date(2024, 1, 15, 6, 0)
        #expect(next(AlarmEntry(hour: 7, isEnabled: false, repeatWeekdays: [], backupMinutes: 15), after: ref, skipping: false) == nil)
        #expect(next(AlarmEntry(hour: 7, repeatWeekdays: [], backupMinutes: nil), after: ref, skipping: false) == nil)
    }

    // MARK: - Stop suppression

    @Test
    func suppression_blocksTheDeadlineThatWasCanceled() {
        let canceledAt = date(2024, 1, 15, 7, 0)
        #expect(BackupAlarmLogic.isSuppressed(
            nextFireDate: date(2024, 1, 15, 7, 15),
            canceledAt: canceledAt
        ))
    }

    @Test
    func suppression_allowsNextOccurrence() {
        let canceledAt = date(2024, 1, 15, 7, 0)
        #expect(!BackupAlarmLogic.isSuppressed(
            nextFireDate: date(2024, 1, 22, 7, 15),
            canceledAt: canceledAt
        ))
    }

    @Test
    func suppression_nilDateIsNotSuppressed() {
        #expect(!BackupAlarmLogic.isSuppressed(
            nextFireDate: nil,
            canceledAt: date(2024, 1, 15, 7, 0)
        ))
    }

    // MARK: - BackupSyncDiff

    private func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    @Test
    func diff_newEntry_schedules() {
        let entry = AlarmEntry(id: uuid(1), backupMinutes: 15)
        let diff = BackupAlarmLogic.computeBackupSyncDiff(
            oldMap: [:], entries: [entry], activeStates: [:]
        )
        #expect(diff.keptMap.isEmpty)
        #expect(diff.cancelEntryIDs.isEmpty)
        #expect(diff.scheduleEntries.map(\.id) == [entry.id])
    }

    @Test
    func diff_alerting_isKept() {
        let entry = AlarmEntry(id: uuid(1), backupMinutes: 15)
        let alarmID = uuid(99)
        let diff = BackupAlarmLogic.computeBackupSyncDiff(
            oldMap: [entry.id: alarmID],
            entries: [entry],
            activeStates: [alarmID: .alerting]
        )
        #expect(diff.keptMap[entry.id] == alarmID)
        #expect(diff.scheduleEntries.isEmpty)
        #expect(diff.cancelEntryIDs.isEmpty)
    }

    @Test
    func diff_countdown_isKept() {
        let entry = AlarmEntry(id: uuid(1), backupMinutes: 15)
        let alarmID = uuid(99)
        let diff = BackupAlarmLogic.computeBackupSyncDiff(
            oldMap: [entry.id: alarmID],
            entries: [entry],
            activeStates: [alarmID: .countdown]
        )
        #expect(diff.keptMap[entry.id] == alarmID)
    }

    @Test
    func diff_disabled_cancels() {
        let entry = AlarmEntry(id: uuid(1), isEnabled: false, backupMinutes: 15)
        let diff = BackupAlarmLogic.computeBackupSyncDiff(
            oldMap: [entry.id: uuid(99)],
            entries: [entry],
            activeStates: [:]
        )
        #expect(diff.cancelEntryIDs == [entry.id])
        #expect(diff.scheduleEntries.isEmpty)
    }

    @Test
    func diff_backupTurnedOff_cancels() {
        let entry = AlarmEntry(id: uuid(1), backupMinutes: nil)
        let diff = BackupAlarmLogic.computeBackupSyncDiff(
            oldMap: [entry.id: uuid(99)],
            entries: [entry],
            activeStates: [:]
        )
        #expect(diff.cancelEntryIDs == [entry.id])
    }

    @Test
    func diff_deleted_cancels() {
        let entryID = uuid(1)
        let diff = BackupAlarmLogic.computeBackupSyncDiff(
            oldMap: [entryID: uuid(99)],
            entries: [],
            activeStates: [:]
        )
        #expect(diff.cancelEntryIDs == [entryID])
    }

    @Test
    func diff_scheduled_isRescheduled() {
        let entry = AlarmEntry(id: uuid(1), backupMinutes: 20)
        let oldID = uuid(99)
        let diff = BackupAlarmLogic.computeBackupSyncDiff(
            oldMap: [entry.id: oldID],
            entries: [entry],
            activeStates: [oldID: .scheduled]
        )
        #expect(diff.rescheduleAlarmIDs[entry.id] == oldID)
        #expect(diff.scheduleEntries.map(\.id) == [entry.id])
    }

    @Test
    func diff_suppressed_keepsTheNextBackup() {
        // 停止直後は、Intent が登録した次回分をそのまま残す（消して再登録しない）
        let entry = AlarmEntry(id: uuid(1), backupMinutes: 15)
        let nextID = uuid(99)
        let diff = BackupAlarmLogic.computeBackupSyncDiff(
            oldMap: [entry.id: nextID],
            entries: [entry],
            activeStates: [nextID: .scheduled],
            suppressedEntryIDs: [entry.id]
        )
        #expect(diff.keptMap[entry.id] == nextID)
        #expect(diff.scheduleEntries.isEmpty)
        #expect(diff.rescheduleAlarmIDs.isEmpty)
        #expect(diff.cancelEntryIDs.isEmpty)
    }

    @Test
    func diff_suppressedWithoutMap_doesNotSchedule() {
        let entry = AlarmEntry(id: uuid(1), backupMinutes: 15)
        let diff = BackupAlarmLogic.computeBackupSyncDiff(
            oldMap: [:],
            entries: [entry],
            activeStates: [:],
            suppressedEntryIDs: [entry.id]
        )
        #expect(diff.scheduleEntries.isEmpty)
    }

    @Test
    func diff_ignoresEntriesWithoutBackup() {
        let entry = AlarmEntry(id: uuid(1), backupMinutes: nil)
        let diff = BackupAlarmLogic.computeBackupSyncDiff(
            oldMap: [:], entries: [entry], activeStates: [:]
        )
        #expect(diff.scheduleEntries.isEmpty)
        #expect(diff.cancelEntryIDs.isEmpty)
    }
}
