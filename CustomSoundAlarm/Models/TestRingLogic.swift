import Foundation

/// 「試しに鳴らす」の純ロジック（#109）。
///
/// - 本物の AlarmKit で 5 秒後に一度だけ鳴らす
/// - AlarmStore には保存しない（アラーム一覧・本番アラームに影響させない）
/// - 停止・60 秒経過・次回起動時の reconcile で確実にキャンセルする
enum TestRingLogic {

    /// 登録から鳴るまでの秒数
    static let delay: TimeInterval = 1

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

    /// 押してから鳴るまでの秒数の区分（#310）。
    /// `test_ring_alerted` の `wait_bucket` にそのまま送る。
    enum WaitBucket: String, CaseIterable, Equatable, Sendable {
        case under2 = "<2"
        case twoToFour = "2-4"
        case fourToSeven = "4-7"
        case sevenToFifteen = "7-15"
        case fifteenPlus = "15+"
    }

    /// 押してから鳴るまでの秒数を区分に分ける。
    /// 音を作る時間も含めるため、押した瞬間から数えた秒数を渡す。
    static func waitBucket(seconds: TimeInterval) -> WaitBucket {
        if seconds < 2 { return .under2 }
        if seconds < 4 { return .twoToFour }
        if seconds < 7 { return .fourToSeven }
        if seconds < 15 { return .sevenToFifteen }
        return .fifteenPlus
    }

    // MARK: - ボタンの状態（#310）

    /// 「試しに鳴らす」ボタン1つの中身。行を増やさず、文字とアイコンだけを変える。
    enum ButtonState: String, Equatable, Sendable {
        /// 待機。押せる。
        case idle
        /// 押した瞬間から鳴るまで。音を作る時間も含む。押せない。
        case waiting
        /// 試しのアラームが `.alerting` になった。押せない。
        case ringing

        /// ボタンに出す文言のキー。
        var titleKey: String {
            switch self {
            case .idle: "test_ring_title"
            case .waiting: "test_ring_waiting"
            case .ringing: "test_ring_ringing"
            }
        }

        /// 押せるのは待機のときだけ。
        var isEnabled: Bool { self == .idle }

        /// アイコンを小さく揺らすのは、鳴るのを待っている間だけ。
        var wigglesIcon: Bool { self == .waiting }
    }

    /// ボタンの状態を変えるきっかけ。
    enum ButtonEvent: Equatable, Sendable {
        /// 押した（音を作る前）。
        case press
        /// 試しのアラームが鳴り始めた（`alarmUpdates` の `.alerting`）。
        case alerting
        /// 試しのアラームが一覧から消えた（止めた・掃除された）。
        case disappeared
        /// 登録に失敗した。
        case failed
        /// 60 秒たっても鳴らなかった。
        case timeout
    }

    /// 状態の移り変わり。時間ではなく、押した・鳴った・消えたで決める。
    /// 60 秒の待ちは押した瞬間から数える（`cleanupAfter`）。
    static func next(state: ButtonState, event: ButtonEvent) -> ButtonState {
        switch (state, event) {
        case (.idle, .press):
            return .waiting
        case (.waiting, .alerting):
            return .ringing
        case (.waiting, .disappeared), (.waiting, .failed), (.waiting, .timeout):
            return .idle
        case (.ringing, .disappeared):
            return .idle
        default:
            // 鳴っている間の timeout では止めない。止めたときだけ待機へ戻す。
            return state
        }
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
