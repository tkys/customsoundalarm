import Foundation

/// アナリティクス用の区分（バケット）変換。純粋関数・単体テスト対象。
/// 生の秒数を送らず区分で送ることで、ダッシュボードで「一瞬見て閉じた」か
/// 「朝まで置いた」かを判別できる粒度に保つ（秒単位の精度は不要）。
enum AnalyticsBuckets {

    /// ベッドサイドモードの滞在時間（秒）→ 滞在区分。
    ///
    /// | 区分 | 範囲 |
    /// |---|---|
    /// | `under_1min` | 0秒以上 1分未満 |
    /// | `1_5min` | 1分以上 5分未満 |
    /// | `5_30min` | 5分以上 30分未満 |
    /// | `30min_2h` | 30分以上 2時間未満 |
    /// | `over_2h` | 2時間以上 |
    static func durationBucket(seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60: return "under_1min"
        case ..<300: return "1_5min"
        case ..<1800: return "5_30min"
        case ..<7200: return "30min_2h"
        default: return "over_2h"
        }
    }

    /// 音源の長さ（秒）→ 秒数区分。
    /// Pro の制限値候補として現実的な「1分」「5分」の境界を含める。
    ///
    /// | 区分 | 範囲 |
    /// |---|---|
    /// | `under_1min` | 0秒以上 1分未満 |
    /// | `1_5min` | 1分以上 5分未満 |
    /// | `5_15min` | 5分以上 15分未満 |
    /// | `over_15min` | 15分以上 |
    static func secondsBucket(seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60: return "under_1min"
        case ..<300: return "1_5min"
        case ..<900: return "5_15min"
        default: return "over_15min"
        }
    }
}