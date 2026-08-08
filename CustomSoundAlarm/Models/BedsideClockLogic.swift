import Foundation
import SwiftUI

/// ベッドサイド時計モードの純粋ロジック（UI 非依存・単体テスト対象）。
enum BedsideClockLogic {

    // MARK: - 焼き付き対策オフセット

    /// 焼き付き対策のために表示位置を微小移動させるオフセット。
    /// 約5分周期で最大 ±12pt の範囲をランダムに見せかけて規則的に移動する。
    ///
    /// - Parameter date: 現在時刻
    /// - Returns: オフセット（pt 単位）。x/y ともに [-12, 12] の範囲。
    static func clockOffset(for date: Date) -> CGSize {
        // 5分（300秒）を1周期とする
        let cycleSeconds: TimeInterval = 300
        let maxOffset: CGFloat = 12

        let epoch = date.timeIntervalSinceReferenceDate
        let phase = (epoch.truncatingRemainder(dividingBy: cycleSeconds)) / cycleSeconds

        // 2つの異なる周期の正弦波で x/y を生成（規則的だが自然に見える移動）
        let x = maxOffset * sin(phase * 2 * .pi)
        let y = maxOffset * sin(phase * 2 * .pi + .pi / 2)

        return CGSize(width: x, height: y)
    }

    /// オフセットが想定範囲内（±maxOffset）に収まっているかを検証用に返す
    static func isOffsetWithinRange(_ offset: CGSize, maxOffset: CGFloat = 12) -> Bool {
        abs(offset.width) <= maxOffset && abs(offset.height) <= maxOffset
    }

    // MARK: - 次のアラーム表示

    /// 次のアラーム時刻の表示文字列を生成する。
    /// - Parameters:
    ///   - alarms: 全アラーム
    ///   - currentDate: 現在時刻
    ///   - calendar: カレンダー（テスト用に注入可能）
    /// - Returns: 表示文字列。アラームが無い場合は nil。
    static func nextAlarmText(
        alarms: [AlarmEntry],
        currentDate: Date,
        calendar: Calendar = .current
    ) -> String? {
        let enabled = alarms.filter(\.isEnabled)
        guard let next = enabled.compactMap({ $0.nextFireDate(from: currentDate, calendar: calendar) })
            .sorted()
            .first
        else { return nil }

        return formatAlarmDate(next, reference: currentDate, calendar: calendar)
    }

    /// アラーム日時を表示用にフォーマットする（当日は時刻のみ、翌日以降は日付＋時刻）。
    private static func formatAlarmDate(_ fire: Date, reference: Date, calendar: Calendar) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        let timeStr = timeFormatter.string(from: fire)

        // 当日か翌日かを判定
        let fireDay = calendar.dateComponents([.year, .month, .day], from: fire)
        let refDay = calendar.dateComponents([.year, .month, .day], from: reference)
        let refTomorrow = calendar.date(byAdding: .day, value: 1, to: reference)!
        let tomorrowDay = calendar.dateComponents([.year, .month, .day], from: refTomorrow)

        if fireDay == refDay {
            // 当日: "Today 7:00" / "今日 7:00"
            return "\(String(localized: "bedside_today")) \(timeStr)"
        } else if fireDay == tomorrowDay {
            // 翌日: "Tomorrow 7:00" / "明日 7:00"
            return "\(String(localized: "bedside_tomorrow")) \(timeStr)"
        } else {
            // それ以降: 日付 + 時刻
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short
            return dateFormatter.string(from: fire)
        }
    }

    // MARK: - 時計フォーマット

    /// システム設定に基づいて 24時間表示かどうかを判定する。
    /// - Parameter date: 現在時刻（フォーマット確認用）
    /// - Returns: true のとき 24時間表示
    static func is24HourFormat(for date: Date = Date()) -> Bool {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        let formatted = formatter.string(from: date)
        // AM/PM が含まれていなければ 24時間表示
        return !formatted.contains("AM") && !formatted.contains("PM")
            && !formatted.contains("午前") && !formatted.contains("午後")
    }
}
