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

    // MARK: - Schedule

    @Test
    func schedule_sameDay() {
        let plan = BackupAlarmLogic.schedule(
            hour: 7, minute: 0, backupMinutes: 15, repeatWeekdays: [2, 4]
        )
        #expect(plan == .init(hour: 7, minute: 15, repeatWeekdays: [2, 4]))
    }

    @Test
    func schedule_crossesMidnight_shiftsWeekday() {
        let plan = BackupAlarmLogic.schedule(
            hour: 23, minute: 50, backupMinutes: 20, repeatWeekdays: [7]
        )
        #expect(plan.hour == 0)
        #expect(plan.minute == 10)
        #expect(plan.repeatWeekdays == [1], "土曜+1日 = 日曜")
    }

    @Test
    func schedule_exactMidnight_shiftsWeekday() {
        let plan = BackupAlarmLogic.schedule(
            hour: 23, minute: 30, backupMinutes: 30, repeatWeekdays: [2]
        )
        #expect(plan.hour == 0)
        #expect(plan.minute == 0)
        #expect(plan.repeatWeekdays == [3])
    }

    @Test
    func schedule_oneTime_staysOneTime() {
        let plan = BackupAlarmLogic.schedule(
            hour: 23, minute: 50, backupMinutes: 20, repeatWeekdays: []
        )
        #expect(plan.hour == 0)
        #expect(plan.minute == 10)
        #expect(plan.repeatWeekdays.isEmpty)
    }

    @Test
    func shiftWeekday_wraps() {
        #expect(BackupAlarmLogic.shiftWeekday(1, by: 0) == 1)
        #expect(BackupAlarmLogic.shiftWeekday(7, by: 1) == 1)
        #expect(BackupAlarmLogic.shiftWeekday(1, by: -1) == 7)
    }

    // MARK: - nextFireDate

    @Test
    func nextFireDate_sameDay() {
        // 2024-01-15 は月曜。土曜の設定を月曜に読む形ではなく、月曜繰り返しで検証
        let entry = AlarmEntry(hour: 7, minute: 0, repeatWeekdays: [2], backupMinutes: 15)
        let ref = date(2024, 1, 14, 12, 0) // 日曜

        let fire = BackupAlarmLogic.nextFireDate(for: entry, from: ref, calendar: Self.cal)
        #expect(fire == date(2024, 1, 15, 7, 15))
    }

    @Test
    func nextFireDate_crossesMidnightToNextWeekday() {
        // 月曜 23:50 + 20分 = 火曜 00:10
        let entry = AlarmEntry(hour: 23, minute: 50, repeatWeekdays: [2], backupMinutes: 20)
        let ref = date(2024, 1, 15, 23, 55) // 月曜

        let fire = BackupAlarmLogic.nextFireDate(for: entry, from: ref, calendar: Self.cal)
        #expect(fire == date(2024, 1, 16, 0, 10))
    }

    @Test
    func nextFireDate_oneTime_futureToday() {
        let entry = AlarmEntry(hour: 7, minute: 0, repeatWeekdays: [], backupMinutes: 15)
        let ref = date(2024, 1, 15, 6, 0)

        let fire = BackupAlarmLogic.nextFireDate(for: entry, from: ref, calendar: Self.cal)
        #expect(fire == date(2024, 1, 15, 7, 15))
    }

    @Test
    func nextFireDate_oneTime_pastToday_usesTomorrow() {
        let entry = AlarmEntry(hour: 7, minute: 0, repeatWeekdays: [], backupMinutes: 15)
        let ref = date(2024, 1, 15, 8, 0)

        let fire = BackupAlarmLogic.nextFireDate(for: entry, from: ref, calendar: Self.cal)
        #expect(fire == date(2024, 1, 16, 7, 15))
    }

    @Test
    func nextFireDate_nilWhenDisabledOrOff() {
        let ref = date(2024, 1, 15, 6, 0)
        #expect(BackupAlarmLogic.nextFireDate(
            for: AlarmEntry(hour: 7, isEnabled: false, repeatWeekdays: [], backupMinutes: 15),
            from: ref, calendar: Self.cal
        ) == nil)
        #expect(BackupAlarmLogic.nextFireDate(
            for: AlarmEntry(hour: 7, repeatWeekdays: [], backupMinutes: nil),
            from: ref, calendar: Self.cal
        ) == nil)
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
        // 時刻変更や通常同期では、既存の .scheduled を登録し直す（本体と同じ規則）
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
    func diff_missingActiveState_isRescheduled() {
        let entry = AlarmEntry(id: uuid(1), backupMinutes: 20)
        let oldID = uuid(99)
        let diff = BackupAlarmLogic.computeBackupSyncDiff(
            oldMap: [entry.id: oldID],
            entries: [entry],
            activeStates: [:]
        )
        #expect(diff.rescheduleAlarmIDs[entry.id] == oldID)
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
