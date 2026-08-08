import Foundation
import SwiftUI

/// ベッドサイド時計モードの純粋ロジック（UI 非依存・単体テスト対象）。
enum BedsideClockLogic {

    // MARK: - 焼き付き対策オフセット

    /// 焼き付き対策のために表示位置を微小移動させるオフセット。
    /// 約5分周期で最大 ±12pt の範囲をランダムに見せかけて規則的に移動する。
    static func clockOffset(for date: Date) -> CGSize {
        let cycleSeconds: TimeInterval = 300
        let maxOffset: CGFloat = 12
        let epoch = date.timeIntervalSinceReferenceDate
        let phase = (epoch.truncatingRemainder(dividingBy: cycleSeconds)) / cycleSeconds
        let x = maxOffset * sin(phase * 2 * .pi)
        let y = maxOffset * sin(phase * 2 * .pi + .pi / 2)
        return CGSize(width: x, height: y)
    }

    static func isOffsetWithinRange(_ offset: CGSize, maxOffset: CGFloat = 12) -> Bool {
        abs(offset.width) <= maxOffset && abs(offset.height) <= maxOffset
    }

    // MARK: - 次のアラーム

    /// 次のアラームの発火日時を返す。アラーム未設定時は nil。
    static func nextAlarmFireDate(
        alarms: [AlarmEntry],
        currentDate: Date,
        calendar: Calendar = .current
    ) -> Date? {
        alarms.filter(\.isEnabled)
            .compactMap { $0.nextFireDate(from: currentDate, calendar: calendar) }
            .sorted()
            .first
    }

    /// 次のアラーム時刻の表示文字列（時刻のみ）。
    static func nextAlarmText(
        alarms: [AlarmEntry],
        currentDate: Date,
        calendar: Calendar = .current
    ) -> String? {
        guard let next = nextAlarmFireDate(alarms: alarms, currentDate: currentDate, calendar: calendar) else { return nil }
        return formatAlarmDate(next, reference: currentDate, calendar: calendar)
    }

    /// 次のアラームまでのカウントダウン文字列（AlarmCountdown.durationString を使用）。
    /// アラーム未設定時は nil。
    static func countdownText(
        alarms: [AlarmEntry],
        currentDate: Date,
        calendar: Calendar = .current
    ) -> String? {
        guard let fire = nextAlarmFireDate(alarms: alarms, currentDate: currentDate, calendar: calendar) else { return nil }
        return AlarmCountdown.untilString(from: currentDate, to: fire)
    }

    private static func formatAlarmDate(_ fire: Date, reference: Date, calendar: Calendar) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        let timeStr = timeFormatter.string(from: fire)

        let fireDay = calendar.dateComponents([.year, .month, .day], from: fire)
        let refDay = calendar.dateComponents([.year, .month, .day], from: reference)
        let refTomorrow = calendar.date(byAdding: .day, value: 1, to: reference)!
        let tomorrowDay = calendar.dateComponents([.year, .month, .day], from: refTomorrow)

        if fireDay == refDay {
            return "\(String(localized: "bedside_today")) \(timeStr)"
        } else if fireDay == tomorrowDay {
            return "\(String(localized: "bedside_tomorrow")) \(timeStr)"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short
            return dateFormatter.string(from: fire)
        }
    }

    // MARK: - 時計フォーマット

    static func is24HourFormat(for date: Date = Date()) -> Bool {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        let formatted = formatter.string(from: date)
        return !formatted.contains("AM") && !formatted.contains("PM")
            && !formatted.contains("午前") && !formatted.contains("午後")
    }

    // MARK: - 配色テーマ

    /// ベッドサイド時計の配色テーマ。
    enum ColorTheme: String, CaseIterable, Sendable {
        case white
        case amber

        var displayName: String {
            switch self {
            case .white: String(localized: "bedside_theme_white")
            case .amber: String(localized: "bedside_theme_amber")
            }
        }

        /// 時計文字の色
        var clockColor: Color {
            switch self {
            case .white: .white.opacity(0.85)
            case .amber: Color(red: 1.0, green: 0.5, blue: 0.1).opacity(0.85)
            }
        }

        /// アラーム情報の色
        var infoColor: Color {
            switch self {
            case .white: .white.opacity(0.5)
            case .amber: Color(red: 1.0, green: 0.5, blue: 0.1).opacity(0.5)
            }
        }

        /// 警告の色
        var warningColor: Color {
            switch self {
            case .white: .orange.opacity(0.8)
            case .amber: Color(red: 1.0, green: 0.4, blue: 0.05).opacity(0.9)
            }
        }
    }

    // MARK: - 輝度制御（純粋関数）

    /// モード開始時の初期輝度を算出する。
    /// 元の輝度の半分（最低 0.05）に下げる。
    static func dimmedBrightness(originalBrightness: CGFloat) -> CGFloat {
        max(0.05, originalBrightness * 0.5)
    }

    /// アイドル時（一定時間操作なし）のさらに減光した輝度。
    static func idleBrightness(originalBrightness: CGFloat) -> CGFloat {
        max(0.02, originalBrightness * 0.15)
    }
}
