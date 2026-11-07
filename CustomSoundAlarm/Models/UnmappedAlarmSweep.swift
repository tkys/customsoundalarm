import Foundation
import AlarmKit

/// 対応表に無いのに AlarmKit に残っているアラーム（取り残し）を見つける純ロジック。
///
/// 取り残しはアプリの一覧に出ず、削除もできず、毎日その時刻に鳴り続ける
/// （App Store レビュー「設定していないのに0時に鳴る」・1.8.0）。
/// 同期の途中打ち切りで、登録済みなのに対応表に書かれなかったものが原因。
enum UnmappedAlarmSweep {

    /// 停止 Intent の直後は掃除しない時間（秒）。
    /// Intent は寝過ごし防止の次回分を AlarmKit に直接登録し、対応表を後から保存するため、
    /// その間に掃除すると正しいアラームを消してしまう。
    static let stopIntentQuietWindow: TimeInterval = 5 * 60

    /// この同期で掃除してよいか。
    /// - `intent`（停止によるバックグラウンド起動）では行わない
    /// - 停止 Intent から `stopIntentQuietWindow` 以内は行わない
    static func shouldSweep(
        trigger: AlarmSyncTrigger,
        now: Date,
        lastStopIntentAt: Date?
    ) -> Bool {
        guard trigger != .intent else { return false }
        guard let lastStopIntentAt else { return true }
        let elapsed = now.timeIntervalSince(lastStopIntentAt)
        // 時計が戻された（elapsed < 0）ときも、念のため掃除しない
        return elapsed >= stopIntentQuietWindow
    }

    /// 取り消すアラームの ID。
    /// 既知の ID（本体・最終アラームの対応表、試し鳴らし、登録処理中）に無く、
    /// 待機中（`.scheduled`）のものだけを対象にする。鳴動中・スヌーズ中・一時停止中は触らない。
    static func orphanIDs(
        snapshots: [AlarmSnapshot],
        knownIDs: Set<Alarm.ID>
    ) -> [Alarm.ID] {
        snapshots
            .filter { $0.state == .scheduled && !knownIDs.contains($0.id) }
            .map(\.id)
    }
}
