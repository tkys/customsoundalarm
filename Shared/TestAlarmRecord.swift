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
    /// 押した瞬間の時刻（#310）。音を作る時間も待ち時間に含める。
    let scheduledAt: Date
    let kind: TestRingKind
    /// この試し鳴らしで音を作ったか（プレイリスト・フェードイン・大きくした版・#310）。
    /// 以前の記録には無いため optional。
    let rendered: Bool?

    init(
        id: UUID,
        scheduledAt: Date,
        kind: TestRingKind,
        rendered: Bool? = nil
    ) {
        self.id = id
        self.scheduledAt = scheduledAt
        self.kind = kind
        self.rendered = rendered
    }
}
