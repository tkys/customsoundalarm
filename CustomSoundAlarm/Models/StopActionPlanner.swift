import Foundation
import AlarmKit

/// 停止時に実行する操作（#110）。純粋関数の出力としてテストする。
enum StopAction: Equatable, Sendable {
    /// 指定した AlarmKit アラームを取り消す
    case cancel(alarmID: UUID)
    /// 指定した AlarmKit アラームを止める（繰り返しスケジュールは残す）
    case stop(alarmID: UUID)
    /// そのアラームの次回分の最終アラームを登録する
    case scheduleNextBackup(entryID: UUID)
}

/// 停止されたアラームに応じて「何をすべきか」を決める純粋関数。
///
/// 重要:
/// - 最終アラームを止めても、本体は **cancel しない**（繰り返しが消えるため）。
///   スヌーズ待機中（`.countdown`）のときだけ `stop` する。
/// - 本体を止めたら、今回の最終アラームは cancel し、次回分を登録する。
enum StopActionPlanner {

    static func plan(
        stoppedAlarmID: UUID,
        primary: [UUID: UUID],
        backup: [UUID: UUID],
        primaryState: Alarm.State?,
        hasNextBackup: Bool
    ) -> [StopAction] {
        switch AlarmIDMaps.role(of: stoppedAlarmID, primary: primary, backup: backup) {
        case .primary(let entryID):
            var actions: [StopAction] = []
            if let backupID = backup[entryID] {
                actions.append(.cancel(alarmID: backupID))
            }
            if hasNextBackup {
                actions.append(.scheduleNextBackup(entryID: entryID))
            }
            return actions

        case .backup(let entryID):
            var actions: [StopAction] = []
            // 本体の繰り返しスケジュールを消さない。スヌーズ中だけ止める
            if let primaryID = primary[entryID], primaryState == .countdown {
                actions.append(.stop(alarmID: primaryID))
            }
            if hasNextBackup {
                actions.append(.scheduleNextBackup(entryID: entryID))
            }
            return actions

        case .unknown:
            return []
        }
    }
}
