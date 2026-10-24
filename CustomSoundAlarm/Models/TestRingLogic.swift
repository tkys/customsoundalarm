import Foundation

/// 「試しに鳴らす」の純ロジック（#109）。
///
/// - 本物の AlarmKit で 5 秒後に一度だけ鳴らす
/// - AlarmStore には保存しない（アラーム一覧・本番アラームに影響させない）
/// - 停止・60 秒経過・次回起動時の reconcile で確実にキャンセルする
enum TestRingLogic {

    /// 登録から鳴るまでの秒数
    static let delay: TimeInterval = 5

    /// 停止されなかった試しアラームを掃除するまでの秒数
    static let cleanupAfter: TimeInterval = 60

    /// AlarmKit から既に消えている場合に「試しの停止」と判定する猶予。
    /// 5 秒後に鳴るため、停止 Intent は登録から数秒以内に走る。
    static let recentWindow: TimeInterval = 120

    /// 試しアラームの登録計画。AlarmKit の型に依存せずテストできる形にする。
    struct Plan: Equatable, Sendable {
        /// 発火日時（`.fixed` スケジュールに渡す）
        let fireDate: Date
        let soundFileName: String
        let kind: TestRingKind

        /// 一回限り（繰り返しなし）
        var repeatsNever: Bool { true }
        /// スヌーズなし
        var snoozeMinutes: Int { 0 }
    }

    /// 5 秒後の一回限りの計画を作る。
    static func makePlan(
        now: Date,
        soundFileName: String,
        kind: TestRingKind
    ) -> Plan {
        Plan(
            fireDate: now.addingTimeInterval(delay),
            soundFileName: soundFileName,
            kind: kind
        )
    }

    /// 掃除の結果。
    struct CleanupResult: Equatable, Sendable {
        /// 残す記録
        let remaining: [TestAlarmRecord]
        /// キャンセルすべき AlarmKit の ID
        let expiredIDs: [UUID]
    }

    /// 登録から 60 秒を過ぎた試しアラームを特定する。
    /// アプリ側（AlarmScheduler）とテストの双方がこの関数を通る。
    static func cleanup(
        records: [TestAlarmRecord],
        now: Date,
        ttl: TimeInterval = cleanupAfter
    ) -> CleanupResult {
        var remaining: [TestAlarmRecord] = []
        var expiredIDs: [UUID] = []
        for record in records {
            if now.timeIntervalSince(record.scheduledAt) >= ttl {
                expiredIDs.append(record.id)
            } else {
                remaining.append(record)
            }
        }
        return CleanupResult(remaining: remaining, expiredIDs: expiredIDs)
    }

    /// 停止 Intent が「試しアラームの停止」かどうか。
    ///
    /// 停止 Intent にはアラーム ID が渡らないため、AlarmKit の現在の一覧と
    /// `AppGroup.testAlarmRecords` を照合する。停止時点で既に一覧から消えている
    /// 場合は、直近（`recentWindow` 以内）に登録した試しアラームがあれば試しとみなす。
    /// 本番アラームが鳴っている（alerting）ときは、試しの記録が残っていても
    /// 本番の停止として扱う（誤って test_ring_stopped を送らない）。
    static func isTestStop(
        activeIDs: Set<UUID>,
        alertingIDs: Set<UUID>,
        records: [TestAlarmRecord],
        now: Date
    ) -> Bool {
        let testIDs = Set(records.map(\.id))
        guard !testIDs.isEmpty else { return false }

        if !alertingIDs.isDisjoint(with: testIDs) { return true }
        if !alertingIDs.isEmpty { return false }
        if !activeIDs.isDisjoint(with: testIDs) { return true }

        return records.contains {
            now.timeIntervalSince($0.scheduledAt) <= recentWindow
        }
    }
}
