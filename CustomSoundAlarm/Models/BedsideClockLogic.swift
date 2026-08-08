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

        // MARK: テスト可能な値

        /// 時計文字の不透明度（アンバーは白より高い）
        var clockOpacity: Double {
            switch self {
            case .white: 0.85
            case .amber: 1.0
            }
        }

        /// 情報テキストの不透明度
        var infoOpacity: Double {
            switch self {
            case .white: 0.5
            case .amber: 0.75
            }
        }

        /// 色相（nil = 白）
        var tintRGB: (r: Double, g: Double, b: Double)? {
            switch self {
            case .white: nil
            case .amber: (1.0, 0.65, 0.15)
            }
        }

        // MARK: 値から組み立てる SwiftUI Color

        /// 時計文字の色
        var clockColor: Color {
            baseColor.opacity(clockOpacity)
        }

        /// アラーム情報の色
        var infoColor: Color {
            baseColor.opacity(infoOpacity)
        }

        /// 警告の色
        var warningColor: Color {
            switch self {
            case .white: .orange.opacity(0.8)
            case .amber: Color(red: 1.0, green: 0.55, blue: 0.1).opacity(0.95)
            }
        }

        private var baseColor: Color {
            if let rgb = tintRGB {
                Color(red: rgb.r, green: rgb.g, blue: rgb.b)
            } else {
                .white
            }
        }
    }

    // MARK: - 輝度制御（純粋関数）

    /// モード開始時の初期輝度を算出する。
    /// 元の輝度にユーザー設定のオフセット倍率を適用する（最低 0.1）。
    /// 既定は0.7（明るめ）：暗所で時刻が読めることを基準。暗くしたい人はスライダーで下げられる。
    static func dimmedBrightness(originalBrightness: CGFloat, userOffset: CGFloat = 0.7) -> CGFloat {
        max(0.1, originalBrightness * userOffset)
    }

    /// アイドル時（一定時間操作なし）の減光輝度。
    /// ユーザー設定のオフセットからさらに 60% に下げる（最低 0.05）。
    static func idleBrightness(originalBrightness: CGFloat, userOffset: CGFloat = 0.7) -> CGFloat {
        max(0.05, originalBrightness * userOffset * 0.6)
    }

    // MARK: - 設定

    /// ベッドサイド時計のユーザー設定（永続化対象）。
    struct BedsideSettings: Codable, Equatable, Sendable {
        /// 明るさ倍率（0.2〜1.0、既定 0.7）
        var brightnessOffset: CGFloat = 0.7
        /// カウントダウン表示
        var showCountdown: Bool = true
        /// 音名表示
        var showSoundName: Bool = true
        /// 日付表示
        var showDate: Bool = false
        /// 秒表示
        var showSeconds: Bool = false
        /// 配色テーマ
        var colorTheme: String = "white"
        /// 文字サイズ倍率（0.7〜1.5、既定 1.0）
        var fontScale: CGFloat = 1.0

        /// 表示要素の数（時計自体を除く）
        var visibleElementCount: Int {
            var count = 0
            if showCountdown { count += 1 }
            if showSoundName { count += 1 }
            if showDate { count += 1 }
            return count
        }
    }

    /// 表示要素数に応じた時計のフォントサイズ。
    /// 要素が多いほど時計が小さくなり、少ないほど大きくなる。
    /// ユーザー指定の倍率を適用した最終サイズを返す。
    static func clockFontSize(visibleElementCount: Int, fontScale: CGFloat = 1.0) -> CGFloat {
        let base: CGFloat
        switch visibleElementCount {
        case 0: base = 120
        case 1: base = 110
        case 2: base = 96
        default: base = 84
        }
        return base * fontScale
    }

    /// 時刻文字列を生成する。
    /// - Parameters:
    ///   - date: 現在時刻
    ///   - is24Hour: 24時間表示か
    ///   - showSeconds: 秒表示するか
    static func timeString(for date: Date, is24Hour: Bool, showSeconds: Bool) -> String {
        let formatter = DateFormatter()
        if showSeconds {
            formatter.dateFormat = is24Hour ? "HH:mm:ss" : "h:mm:ss"
        } else {
            formatter.dateFormat = is24Hour ? "HH:mm" : "h:mm"
        }
        return formatter.string(from: date)
    }
}
