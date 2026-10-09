import Foundation

/// アラーム一覧の表示順（#103）。
///
/// 仕様:
/// - 時:分の昇順（0:00 → 23:59）。次回発火日時順ではない
/// - 同じ時刻は保存順（作成順）を保つ安定ソート。複製は同時刻グループの末尾に並ぶ
/// - 保存順は変えない。表示時だけ並べる
enum AlarmListOrdering {

    /// 表示用の並びにソートする。
    /// - Parameter alarms: 保存順のアラーム配列
    /// - Returns: 時:分の昇順、同値は元の並び順で安定化した配列
    static func sortedForDisplay(_ alarms: [AlarmEntry]) -> [AlarmEntry] {
        alarms.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.hour != rhs.element.hour {
                    return lhs.element.hour < rhs.element.hour
                }
                if lhs.element.minute != rhs.element.minute {
                    return lhs.element.minute < rhs.element.minute
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
