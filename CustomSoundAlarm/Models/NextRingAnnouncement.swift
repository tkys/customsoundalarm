import Foundation

/// 保存直後・一覧でオンにしたときに、次に鳴るまでの時間を1文で出す（#289）。
///
/// 次に鳴る日時は `AlarmEntry.nextFireDate`（休む日・祝日を除く）をそのまま使う。
/// ここでは「24時間未満は残り時間、24時間以上は曜日と時刻」の作り分けと、
/// 画面に出す1文の組み立てだけを行う。
enum NextRingAnnouncement {

    /// 文の作り分け。文言はここで組み立てず、計算だけをテストできるようにする。
    enum Kind: Equatable, Sendable {
        /// 24時間未満。鳴るまでの分（1分未満は1分に切り上げる）。
        case minutes(Int)
        /// 24時間以上。次の鳴る日時。
        case weekday(Date)
    }

    /// 24時間（秒）。ちょうど24時間は「曜日と時刻」で出す。
    static let oneDay: TimeInterval = 24 * 60 * 60

    /// 次に鳴る日時までの作り分け。鳴らない（オフ・不正な時刻）なら nil。
    static func kind(
        for entry: AlarmEntry,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Kind? {
        guard let fire = entry.nextFireDate(from: now, calendar: calendar) else {
            return nil
        }
        return kind(fireDate: fire, now: now)
    }

    /// 発火日時と基準日時から作り分けを返す。
    static func kind(fireDate: Date, now: Date) -> Kind? {
        let interval = fireDate.timeIntervalSince(now)
        guard interval > 0 else { return nil }
        if interval >= oneDay {
            return .weekday(fireDate)
        }
        // 1分未満は「0分後」にせず、1分後に切り上げる。
        return .minutes(max(1, Int(interval / 60)))
    }

    /// 画面に出す1文。例: 「7時間25分後に鳴ります」「月曜 7:30 に鳴ります」。
    static func message(
        for entry: AlarmEntry,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String? {
        guard let kind = kind(for: entry, now: now, calendar: calendar) else {
            return nil
        }
        return message(
            kind: kind,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
    }

    /// 作り分けから1文を組み立てる。
    static func message(
        kind: Kind,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        switch kind {
        case .minutes(let minutes):
            return String(
                format: String(localized: "alarm_will_ring_in"),
                durationText(minutes: minutes)
            )
        case .weekday(let fire):
            let components = calendar.dateComponents(
                in: timeZone,
                from: fire
            )
            let weekday = weekdayText(
                fire,
                locale: locale,
                calendar: calendar,
                timeZone: timeZone
            )
            let time = AlarmTimeFormat.display(
                hour: components.hour ?? 0,
                minute: components.minute ?? 0,
                locale: locale,
                calendar: calendar,
                timeZone: timeZone
            )
            return String(
                format: String(localized: "alarm_will_ring_on_weekday_fmt"),
                weekday,
                time
            )
        }
    }

    /// 「7時間25分」「25分」。既存の残り時間の文言をそのまま使う。
    static func durationText(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0 {
            return String(
                format: String(localized: "countdown_hours_minutes"),
                hours,
                rest
            )
        }
        return String(
            format: String(localized: "countdown_minutes"),
            max(0, rest)
        )
    }

    /// 曜日の名前。日本語は「月曜日」ではなく、短く「月曜」と出す。
    static func weekdayText(
        _ date: Date,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        var style = Date.FormatStyle().weekday(.wide)
        style.locale = locale
        style.calendar = calendar
        style.timeZone = timeZone
        let name = date.formatted(style)
        if locale.language.languageCode?.identifier == "ja" {
            return name.replacingOccurrences(of: "曜日", with: "曜")
        }
        return name
    }

    /// 保存した内容が次に鳴る日時を変えるか（新規・時刻・曜日・休み・オン/オフ）。
    /// 名前や音だけを変えた保存では出さない。
    static func shouldAnnounce(
        isNew: Bool,
        previous: AlarmEntry?,
        updated: AlarmEntry
    ) -> Bool {
        guard !isNew, let previous else { return true }
        return previous.hour != updated.hour
            || previous.minute != updated.minute
            || Set(previous.repeatWeekdays) != Set(updated.repeatWeekdays)
            || Set(previous.skipDates) != Set(updated.skipDates)
            || previous.skipsHolidays != updated.skipsHolidays
            || Set(previous.holidayRingOverrides) != Set(updated.holidayRingOverrides)
            || previous.isEnabled != updated.isEnabled
    }
}
