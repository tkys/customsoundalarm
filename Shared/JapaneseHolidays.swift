import Foundation

/// 日本の国民の祝日（#197）。
///
/// 内閣府の一覧をアプリに持つ。カレンダーの許可は使わない。
/// 振替休日と国民の休日も含める。2026〜2028年。
struct JapaneseHoliday: Codable, Hashable, Sendable, Identifiable {
    /// ローカル日付の `yyyy-MM-dd`
    let dateKey: String
    let name: String

    var id: String { dateKey }
}

enum JapaneseHolidays {
    /// データの最初と最後の年。最後の1年前から更新を促す（#197）。
    static let firstYear = 2026
    static let lastYear = 2028

    /// 内閣府「国民の祝日」2026〜2028（振替休日・国民の休日を含む）。
    static let all: [JapaneseHoliday] = [
        // 2026
        .init(dateKey: "2026-01-01", name: "元日"),
        .init(dateKey: "2026-01-12", name: "成人の日"),
        .init(dateKey: "2026-02-11", name: "建国記念の日"),
        .init(dateKey: "2026-02-23", name: "天皇誕生日"),
        .init(dateKey: "2026-03-20", name: "春分の日"),
        .init(dateKey: "2026-04-29", name: "昭和の日"),
        .init(dateKey: "2026-05-03", name: "憲法記念日"),
        .init(dateKey: "2026-05-04", name: "みどりの日"),
        .init(dateKey: "2026-05-05", name: "こどもの日"),
        .init(dateKey: "2026-05-06", name: "振替休日"),
        .init(dateKey: "2026-07-20", name: "海の日"),
        .init(dateKey: "2026-08-11", name: "山の日"),
        .init(dateKey: "2026-09-21", name: "敬老の日"),
        .init(dateKey: "2026-09-22", name: "国民の休日"),
        .init(dateKey: "2026-09-23", name: "秋分の日"),
        .init(dateKey: "2026-10-12", name: "スポーツの日"),
        .init(dateKey: "2026-11-03", name: "文化の日"),
        .init(dateKey: "2026-11-23", name: "勤労感謝の日"),
        // 2027
        .init(dateKey: "2027-01-01", name: "元日"),
        .init(dateKey: "2027-01-11", name: "成人の日"),
        .init(dateKey: "2027-02-11", name: "建国記念の日"),
        .init(dateKey: "2027-02-23", name: "天皇誕生日"),
        .init(dateKey: "2027-03-21", name: "春分の日"),
        .init(dateKey: "2027-03-22", name: "振替休日"),
        .init(dateKey: "2027-04-29", name: "昭和の日"),
        .init(dateKey: "2027-05-03", name: "憲法記念日"),
        .init(dateKey: "2027-05-04", name: "みどりの日"),
        .init(dateKey: "2027-05-05", name: "こどもの日"),
        .init(dateKey: "2027-07-19", name: "海の日"),
        .init(dateKey: "2027-08-11", name: "山の日"),
        .init(dateKey: "2027-09-20", name: "敬老の日"),
        .init(dateKey: "2027-09-23", name: "秋分の日"),
        .init(dateKey: "2027-10-11", name: "スポーツの日"),
        .init(dateKey: "2027-11-03", name: "文化の日"),
        .init(dateKey: "2027-11-23", name: "勤労感謝の日"),
        // 2028
        .init(dateKey: "2028-01-01", name: "元日"),
        .init(dateKey: "2028-01-10", name: "成人の日"),
        .init(dateKey: "2028-02-11", name: "建国記念の日"),
        .init(dateKey: "2028-02-23", name: "天皇誕生日"),
        .init(dateKey: "2028-03-20", name: "春分の日"),
        .init(dateKey: "2028-04-29", name: "昭和の日"),
        .init(dateKey: "2028-05-03", name: "憲法記念日"),
        .init(dateKey: "2028-05-04", name: "みどりの日"),
        .init(dateKey: "2028-05-05", name: "こどもの日"),
        .init(dateKey: "2028-07-17", name: "海の日"),
        .init(dateKey: "2028-08-11", name: "山の日"),
        .init(dateKey: "2028-09-18", name: "敬老の日"),
        .init(dateKey: "2028-09-22", name: "秋分の日"),
        .init(dateKey: "2028-10-09", name: "スポーツの日"),
        .init(dateKey: "2028-11-03", name: "文化の日"),
        .init(dateKey: "2028-11-23", name: "勤労感謝の日"),
    ]

    private static let byDateKey: [String: JapaneseHoliday] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.dateKey, $0) }
    )

    static func holiday(on dateKey: String) -> JapaneseHoliday? {
        byDateKey[dateKey]
    }

    static func isHoliday(_ date: Date, calendar: Calendar = .current) -> Bool {
        byDateKey[AlarmSkipLogic.dateKey(date, calendar: calendar)] != nil
    }

    /// `start` 以降 `days` 日以内の祝日（開始日を含む）。
    static func upcoming(
        from start: Date,
        days: Int,
        calendar: Calendar = .current
    ) -> [JapaneseHoliday] {
        let fromKey = AlarmSkipLogic.dateKey(start, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: days, to: start) ?? start
        let endKey = AlarmSkipLogic.dateKey(end, calendar: calendar)
        return all.filter { $0.dateKey >= fromKey && $0.dateKey <= endKey }
    }

    /// データの更新を促し始める日（最終年の1年前の1月1日）。
    static func updateWarningDate(calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: lastYear - 1, month: 1, day: 1))
    }

    /// 祝日データの更新時期に入ったか。テストでも使う。
    static func needsUpdate(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let warning = updateWarningDate(calendar: calendar) else { return true }
        return now >= warning
    }
}

extension AlarmSkipLogic {
    /// 祝日データ（2026〜2028）が揃っているか。テスト用。
    static func holidayYearsAreComplete() -> Bool {
        let years = Set(JapaneseHolidays.all.compactMap { Int($0.dateKey.prefix(4)) })
        return years == Set(JapaneseHolidays.firstYear...JapaneseHolidays.lastYear)
    }
}
