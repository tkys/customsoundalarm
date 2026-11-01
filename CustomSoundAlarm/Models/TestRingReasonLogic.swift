import Foundation

/// 「今すぐ鳴らす」が鳴らせない理由（#150）。
/// raw value は `test_ring_failed` の `reason` にそのまま送る安定識別子。変更禁止。
enum TestRingFailureReason: String, Equatable, Sendable {
    /// 許可がまだ（notDetermined）
    case notAuthorized = "not_authorized"
    /// 許可が拒否済み
    case denied = "denied"
    /// AlarmKit への登録に失敗した
    case scheduleError = "schedule_error"
    /// シミュレータ実行中（AlarmKit を鳴らせない）
    case simulator = "simulator"
}

/// 理由の表示情報（表示文言のキーと「設定を開く」の有無・#150）。
struct TestRingReasonDisplay: Equatable, Sendable {
    /// 理由の Localizable キー
    let messageKey: String
    /// 直し方として「設定を開く」を出すか（許可の問題だけ true）
    let showsOpenSettings: Bool
}

/// 「今すぐ鳴らす」の理由表示の純ロジック（#150）。
///
/// 無効化したボタンだけを見せないため、状態 → 表示文言・ボタンの有無を
/// AlarmKit の型に依存せず決める。行の下に理由と直し方をその場で出す。
enum TestRingReasonLogic {

    /// 権限状態 → その場に出す理由（問題がなければ nil）。
    static func permissionReason(permission: TestRingPermission) -> TestRingFailureReason? {
        switch permission {
        case .allowed: return nil
        case .unknown: return .notAuthorized
        case .denied: return .denied
        }
    }

    /// 理由 → 表示情報（文言キー + 「設定を開く」の有無）。
    static func display(for reason: TestRingFailureReason) -> TestRingReasonDisplay {
        switch reason {
        case .notAuthorized:
            TestRingReasonDisplay(
                messageKey: "test_ring_reason_not_authorized",
                showsOpenSettings: true
            )
        case .denied:
            TestRingReasonDisplay(
                messageKey: "test_ring_reason_denied",
                showsOpenSettings: true
            )
        case .scheduleError:
            TestRingReasonDisplay(
                messageKey: "test_ring_failed",
                showsOpenSettings: false
            )
        case .simulator:
            TestRingReasonDisplay(
                messageKey: "test_ring_simulator_unavailable",
                showsOpenSettings: false
            )
        }
    }
}
