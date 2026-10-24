import Foundation
import AlarmKit

/// 最終アラーム（締め切り）の純ロジック（#110）。
///
/// 本体アラームの時刻 + N 分に、同じ曜日で停止のみのアラームを登録する。
/// 日付をまたぐ場合は曜日を +1 日ずらす。
enum BackupAlarmLogic {

    /// 既定の分数
    static let defaultMinutes: Int = 15

    /// 選択肢（分）
    static let minuteOptions: [Int] = [10, 15, 20, 30]

    /// 最終アラームに使う音（#109 で追加した専用音）
    static var soundFileName: String { BackupAlarmSound.fileName }

    /// 本体の時刻から最終アラームの時刻・曜日を計算した結果。
    struct Schedule: Equatable, Sendable {
        let hour: Int
        let minute: Int
        /// 空 = 一回限り
        let repeatWeekdays: [Int]
    }

    /// 曜日（1=日…7=土）を days 日ずらす。
    static func shiftWeekday(_ weekday: Int, by days: Int) -> Int {
        (((weekday - 1 + days) % 7) + 7) % 7 + 1
    }

    /// 本体の設定から最終アラームの時刻・曜日を求める。
    static func schedule(
        hour: Int,
        minute: Int,
        backupMinutes: Int,
        repeatWeekdays: [Int]
    ) -> Schedule {
        let total = hour * 60 + minute + backupMinutes
        let dayShift = total >= 24 * 60 ? 1 : 0
        let wrapped = ((total % (24 * 60)) + (24 * 60)) % (24 * 60)
        let weekdays = repeatWeekdays.isEmpty
            ? []
            : repeatWeekdays.map { shiftWeekday($0, by: dayShift) }
        return Schedule(
            hour: wrapped / 60,
            minute: wrapped % 60,
            repeatWeekdays: weekdays
        )
    }

    /// 本体の設定から最終アラームの次回発火日時を求める（テスト・抑制判定用）。
    /// `AlarmEntry.nextFireDate` と同じ規則（繰り返しは曜日、一回限りは次の時刻）。
    static func nextFireDate(
        for entry: AlarmEntry,
        from referenceDate: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard entry.isEnabled, let backupMinutes = entry.backupMinutes else { return nil }
        let plan = schedule(
            hour: entry.hour,
            minute: entry.minute,
            backupMinutes: backupMinutes,
            repeatWeekdays: entry.repeatWeekdays
        )
        let probe = AlarmEntry(
            id: entry.id,
            hour: plan.hour,
            minute: plan.minute,
            isEnabled: true,
            label: entry.label,
            repeatWeekdays: plan.repeatWeekdays,
            soundFileName: entry.soundFileName,
            snoozeMinutes: entry.snoozeMinutes,
            backupMinutes: nil
        )
        return probe.nextFireDate(from: referenceDate, calendar: calendar)
    }

    // MARK: - Sync diff

    /// 最終アラームの差分同期。
    struct BackupSyncDiff: Sendable {
        var keptMap: [UUID: UUID]
        var cancelEntryIDs: Set<UUID>
        var rescheduleAlarmIDs: [UUID: UUID]
        var scheduleEntries: [AlarmEntry]
    }

    /// `backupAlarmIDMap` の遷移を計算する純粋関数。
    /// 本体の `computeSyncDiff` と同じ規則（鳴動/スヌーズ中だけ維持、それ以外は再登録）。
    static func computeBackupSyncDiff(
        oldMap: [UUID: UUID],
        entries: [AlarmEntry],
        activeStates: [UUID: Alarm.State]
    ) -> BackupSyncDiff {
        let wanted = entries.filter { $0.isEnabled && $0.backupMinutes != nil }
        let wantedIDs = Set(wanted.map(\.id))

        var keptMap: [UUID: UUID] = [:]
        var cancelEntryIDs = Set<UUID>()
        var rescheduleAlarmIDs: [UUID: UUID] = [:]
        var scheduleEntries: [AlarmEntry] = []

        for entryID in oldMap.keys where !wantedIDs.contains(entryID) {
            cancelEntryIDs.insert(entryID)
        }

        for entry in wanted {
            if let alarmID = oldMap[entry.id],
               let state = activeStates[alarmID],
               state == .countdown || state == .alerting || state == .paused {
                keptMap[entry.id] = alarmID
            } else {
                if let oldAlarmID = oldMap[entry.id] {
                    rescheduleAlarmIDs[entry.id] = oldAlarmID
                }
                scheduleEntries.append(entry)
            }
        }

        return BackupSyncDiff(
            keptMap: keptMap,
            cancelEntryIDs: cancelEntryIDs,
            rescheduleAlarmIDs: rescheduleAlarmIDs,
            scheduleEntries: scheduleEntries
        )
    }
}
