import Foundation

/// 画面に出す時刻の書式（#283）。
///
/// 端末の言語と12／24時間制に従う。内部の比較・計測に使う `HH:mm` は
/// `AlarmEntry.timeString` のまま残し、表示だけをこちらに置き換える。
enum AlarmTimeFormat {

    /// 表示用の時刻の内訳。12時間制の AM／PM を数字より小さく出すために使う。
    struct Parts: Equatable, Sendable {
        /// 数字とコロン（例: "5:05" / "17:05"）
        var time: String
        /// AM／PM（例: "PM" / "午後"）。24時間制では nil。
        var period: String?
        /// AM／PM が数字より前にあるか（日本語の12時間制など）。
        var periodFirst: Bool

        /// 読み上げ・フォールバック用の1本の文字列。
        var displayText: String {
            guard let period else { return time }
            return periodFirst ? "\(period)\(time)" : "\(time) \(period)"
        }
    }

    /// 表示用の書式。端末の言語・12／24時間制に従う。
    static func style(
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> Date.FormatStyle {
        var style = Date.FormatStyle()
            .hour(.defaultDigits(amPM: .abbreviated))
            .minute()
        style.locale = locale
        style.calendar = calendar
        style.timeZone = timeZone
        return style
    }

    /// 時・分を表す固定日（表示にだけ使う。日付そのものは出さない）。
    static func date(
        hour: Int,
        minute: Int,
        calendar: Calendar = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> Date? {
        var calendar = calendar
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = timeZone
        components.year = 2001
        components.month = 1
        components.day = 1
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)
    }

    /// 画面に出す時刻の文字列（例: ja「5:05」/ en-US「5:05 PM」/ en-GB「05:05」）。
    static func display(
        hour: Int,
        minute: Int,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        guard let date = date(
            hour: hour,
            minute: minute,
            calendar: calendar,
            timeZone: timeZone
        ) else {
            return String(format: "%02d:%02d", hour, minute)
        }
        return date.formatted(style(
            locale: locale,
            calendar: calendar,
            timeZone: timeZone
        ))
    }

    /// 画面に出す時刻の内訳（AM／PM を小さく出すため）。
    static func parts(
        hour: Int,
        minute: Int,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> Parts {
        guard let date = date(
            hour: hour,
            minute: minute,
            calendar: calendar,
            timeZone: timeZone
        ) else {
            return Parts(
                time: String(format: "%02d:%02d", hour, minute),
                period: nil,
                periodFirst: false
            )
        }
        return parts(for: date, style: style(
            locale: locale,
            calendar: calendar,
            timeZone: timeZone
        ))
    }

    /// 任意の書式（秒つきなど）で、数字と AM／PM を分ける。
    static func parts(for date: Date, style: Date.FormatStyle) -> Parts {
        let attributed = style.attributedStyle.format(date)
        var tokens: [(text: String, isPeriod: Bool)] = []
        for run in attributed.runs {
            let text = String(attributed[run.range].characters)
            let field = run.attributes[
                AttributeScopes.FoundationAttributes.DateFieldAttribute.self
            ]
            tokens.append((text, field == .amPM))
        }

        let time = tokens
            .filter { !$0.isPeriod }
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespaces)
        let period = tokens
            .filter(\.isPeriod)
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespaces)
        let firstMeaningful = tokens.first {
            !$0.text.trimmingCharacters(in: .whitespaces).isEmpty
        }

        return Parts(
            time: time,
            period: period.isEmpty ? nil : period,
            periodFirst: firstMeaningful?.isPeriod == true
        )
    }
}
