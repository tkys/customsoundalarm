import Foundation

/// 保存後のトーストメッセージを計算する純粋関数。
/// トースト判定の3分岐を `AlarmDetailView` に直書きせず、
/// 単体テスト可能な形で切り出す。
///
/// - `willRing`: 有効かつ発火日時が算出可能 → 「○時間○分後に鳴ります」
/// - `isOff`: 無効 → 「このアラームはオフです」
/// - `silent`: 有効だが発火日時が算出不能 → トースト無し（無言で閉じる）
enum PostSaveFeedback: Equatable, Sendable {

    /// 有効で発火までの時間が分かるとき。
    case willRing
    /// 無効時のフィードバック。
    case isOff
    /// 有効だが発火日時が算出不能（例: 不正な時刻）。
    case silent

    /// 保存確定時のフィードバックを判定する。純粋関数（ローカライズ非依存）。
    static func resolve(for entry: AlarmEntry, currentDate: Date) -> PostSaveFeedback {
        if entry.isEnabled, let fire = entry.nextFireDate(from: currentDate) {
            return .willRing
        } else if !entry.isEnabled {
            return .isOff
        }
        return .silent
    }

    /// ローカライズされたトースト文言。`.silent` のとき `nil`。
    func localizedMessage(entry: AlarmEntry, currentDate: Date) -> String? {
        switch self {
        case .willRing:
            guard let fire = entry.nextFireDate(from: currentDate) else { return nil }
            let duration = AlarmCountdown.durationString(from: currentDate, to: fire)
            return String(format: String(localized: "alarm_will_ring_in"), duration)
        case .isOff:
            return String(localized: "alarm_is_off")
        case .silent:
            return nil
        }
    }
}