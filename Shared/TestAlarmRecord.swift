import Foundation

/// 試しに鳴らすアラームの種類（#109）
enum TestRingKind: String, Codable, Hashable, Sendable {
    /// 選択中のサウンド（ユーザーの音／プリセット）
    case own
    /// 最終アラーム専用の音
    case backup
}

/// 試しに鳴らしたアラームの記録（#109）。
/// `AlarmStore` には保存しない。停止・60秒経過・次回起動時の掃除にだけ使う。
struct TestAlarmRecord: Codable, Hashable, Sendable {
    let id: UUID
    let scheduledAt: Date
    let kind: TestRingKind
}
