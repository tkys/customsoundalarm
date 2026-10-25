import Foundation
import AlarmKit

/// 最終アラーム（締め切り）の純ロジック（#110）。
///
/// 最終アラームは「次の1回だけ」を `.fixed(date)` で登録する。
/// 停止時はその場で次回分を登録するため、アプリを開かなくても毎回の締め切りが用意される。
enum BackupAlarmLogic {

    /// 既定の分数
    static let defaultMinutes: Int = 15

    /// 選択肢（分）
    static let minuteOptions: [Int] = [10, 15, 20, 30]

    /// 最終アラームに使う音（#109 で追加した専用音）
    static var soundFileName: String { BackupAlarmSound.fileName }

    /// 次の最終アラーム時刻。
    ///
    /// - `skippingCurrentOccurrence == false`: いまの本体サイクルの締め切りがまだ未来ならそれを返す
    ///   （本体が鳴動/スヌーズ中でも、今日の締め切りを維持する）
    /// - `skippingCurrentOccurrence == true`: いまのサイクルを飛ばして、次の本体発火 + N 分を返す
    ///   （停止時に次回分を登録する用）。一回限りは次回が無いので nil。
    static func nextBackupDate(
        for entry: AlarmEntry,
        after referenceDate: Date,
        skippingCurrentOccurrence: Bool,
        calendar: Calendar = .current
    ) -> Date? {
        guard entry.isEnabled, let minutes = entry.backupMinutes else { return nil }

        if !skippingCurrentOccurrence,
           let current = currentOccurrenceBackupDate(
               for: entry,
               after: referenceDate,
               minutes: minutes,
               calendar: calendar
           ),
           current > referenceDate {
            return current
        }

        // 一回限りの「次回」は作らない
        if skippingCurrentOccurrence && entry.repeatWeekdays.isEmpty {
            return nil
        }

        guard let nextPrimary = entry.nextFireDate(from: referenceDate, calendar: calendar) else {
            return nil
        }
        return nextPrimary.addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// いまのサイクル（今日の本体発火）に対する締め切り。
    /// 今日が繰り返し曜日に含まれない場合は nil。
    private static func currentOccurrenceBackupDate(
        for entry: AlarmEntry,
        after referenceDate: Date,
        minutes: Int,
        calendar: Calendar
    ) -> Date? {
        guard let primaryToday = calendar.date(
            bySettingHour: entry.hour,
            minute: entry.minute,
            second: 0,
            of: referenceDate
        ) else { return nil }

        if !entry.repeatWeekdays.isEmpty {
            let weekday = calendar.component(.weekday, from: primaryToday)
            guard entry.repeatWeekdays.contains(weekday) else { return nil }
        }

        return primaryToday.addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// 説明文に出す「元の時刻」と「寝過ごし防止の時刻」（#119）。
    /// 日付をまたぐ場合は 0:10 のように時計の時刻へ丸める。
    static func displayTimes(
        hour: Int,
        minute: Int,
        backupMinutes: Int
    ) -> (originalHour: Int, originalMinute: Int, backupHour: Int, backupMinute: Int) {
        let total = hour * 60 + minute + backupMinutes
        let wrapped = ((total % (24 * 60)) + (24 * 60)) % (24 * 60)
        return (hour, minute, wrapped / 60, wrapped % 60)
    }

    /// 停止で取り消した締め切りを復活させないための抑制時間（秒）。
    static let suppressionWindow: TimeInterval = 60 * 60

    /// 停止直後の同期で、同じ締め切りを再登録しないための判定。
    /// 次の発生が停止時刻 + 1時間以内なら「いま取り消した締め切り」とみなす。
    static func isSuppressed(nextFireDate: Date?, canceledAt: Date) -> Bool {
        guard let nextFireDate else { return false }
        return nextFireDate <= canceledAt.addingTimeInterval(suppressionWindow)
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
    ///
    /// - 鳴動/スヌーズ中は維持
    /// - 停止直後の抑制中（`suppressedEntryIDs`）は何もしない（次回分を消さない）
    /// - それ以外は次の締め切りで登録し直す
    static func computeBackupSyncDiff(
        oldMap: [UUID: UUID],
        entries: [AlarmEntry],
        activeStates: [UUID: Alarm.State],
        suppressedEntryIDs: Set<UUID> = []
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
            if suppressedEntryIDs.contains(entry.id) {
                // 停止直後: いま登録されている次回分をそのまま残す
                if let alarmID = oldMap[entry.id] {
                    keptMap[entry.id] = alarmID
                }
                continue
            }

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
