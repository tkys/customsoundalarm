import Foundation

/// 次回発火までの残り時間の計算とローカライズ表示。
/// 純粋な時間計算（`components`）と文字列表現（`string`）を分離し、
/// `components` をユニットテストで検証可能にしている。
enum AlarmCountdown {
    /// 残り時間を日/時間/分に分解した結果。
    struct Components: Equatable {
        let days: Int
        let hours: Int
        let minutes: Int
    }

    /// `reference` から `fireDate` までの経過時間を日/時間/分に分解する。
    /// `fireDate` が `reference` より過去の場合は全 0 を返す（負にならない）。
    static func components(from reference: Date, to fireDate: Date) -> Components {
        let interval = max(0, fireDate.timeIntervalSince(reference))
        let totalMinutes = Int(interval / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60
        return Components(days: days, hours: hours, minutes: minutes)
    }

    /// 残り時間を「7時間30分」「45分」「2日3時間」形式（ローカライズ）で返す。
    /// - note: 返り値は素の期間文字列（「あと」等の前置詞は含まない）。
    ///   呼び出し側で `countdown_until`（「あと%@」）等でラップすること。
    static func durationString(from reference: Date, to fireDate: Date) -> String {
        let c = components(from: reference, to: fireDate)
        if c.days >= 1 {
            return String(format: String(localized: "countdown_days_hours"), c.days, c.hours)
        } else if c.hours >= 1 {
            return String(format: String(localized: "countdown_hours_minutes"), c.hours, c.minutes)
        } else {
            return String(format: String(localized: "countdown_minutes"), max(c.minutes, 0))
        }
    }

    /// 行表示用: 「あと7時間30分」のように前置詞付きで返す。
    static func untilString(from reference: Date, to fireDate: Date) -> String {
        let format = String(localized: "countdown_until")
        return String(format: format, durationString(from: reference, to: fireDate))
    }

    /// 残り時間を整数「時間」に切り詰めた値。アナリティクスの `hours_until` 用。
    /// 1時間未満は 0、1日以上は 24 を超える整数になる（DAU/到達時間の粗い分析用）。
    static func hoursUntil(from reference: Date, to fireDate: Date) -> Int {
        let interval = max(0, fireDate.timeIntervalSince(reference))
        return Int(interval / 3600)
    }
}
