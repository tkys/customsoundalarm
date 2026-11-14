import Foundation

/// 追加・編集画面の保存ロジック（#122）。
/// 保存したアラームは必ずオンにする（時計アプリと同じく、保存＝鳴らしたい）。
enum AlarmSaveLogic {

    static func newEntry(
        hour: Int,
        minute: Int,
        label: String,
        repeatWeekdays: [Int],
        soundFileName: String,
        snoozeMinutes: Int,
        backupMinutes: Int?,
        playlistID: UUID? = nil,
        fadeIn: PlaylistFadeIn = .off,
        isEnabled: Bool = true,
        skipsHolidays: Bool = false,
        holidayRingOverrides: [String] = [],
        skipDates: [String] = []
    ) -> AlarmEntry {
        AlarmEntry(
            hour: hour,
            minute: minute,
            isEnabled: isEnabled,
            label: label,
            repeatWeekdays: repeatWeekdays,
            soundFileName: soundFileName,
            snoozeMinutes: snoozeMinutes,
            backupMinutes: backupMinutes,
            playlistID: playlistID,
            fadeIn: fadeIn,
            skipDates: skipDates,
            skipsHolidays: skipsHolidays,
            holidayRingOverrides: holidayRingOverrides
        )
    }

    static func updatedEntry(
        from existing: AlarmEntry,
        hour: Int,
        minute: Int,
        label: String,
        repeatWeekdays: [Int],
        soundFileName: String,
        snoozeMinutes: Int,
        backupMinutes: Int?,
        playlistID: UUID? = nil,
        fadeIn: PlaylistFadeIn = .off,
        skipsHolidays: Bool? = nil,
        holidayRingOverrides: [String]? = nil,
        skipDates: [String]? = nil
    ) -> AlarmEntry {
        var updated = existing
        updated.hour = hour
        updated.minute = minute
        updated.label = label
        updated.repeatWeekdays = repeatWeekdays
        updated.soundFileName = soundFileName
        updated.snoozeMinutes = snoozeMinutes
        updated.backupMinutes = backupMinutes
        updated.playlistID = playlistID
        updated.fadeIn = fadeIn
        if let skipsHolidays { updated.skipsHolidays = skipsHolidays }
        if let holidayRingOverrides { updated.holidayRingOverrides = holidayRingOverrides }
        if let skipDates {
            // 時刻を変えても休む日は残す。曜日を変えたら合わない日付は黙って落とす（#197）
            if repeatWeekdays.isEmpty {
                updated.skipDates = []
            } else {
                let calendar = Calendar.current
                updated.skipDates = skipDates.filter { key in
                    guard let date = AlarmSkipLogic.date(fromKey: key, calendar: calendar) else {
                        return false
                    }
                    return repeatWeekdays.contains(calendar.component(.weekday, from: date))
                }.sorted()
            }
        }
        // 編集画面にオン/オフは置かない。保存したらオン（#122）
        updated.isEnabled = true
        return updated
    }
}

// MARK: - 繰り返し行の要約（#197 レビュー）

/// 繰り返し行に出す文言の材料。テストでは日本語の lproj を渡せる。
struct RepeatSummaryStrings {
    let never: String
    let everyDay: String
    let weekdays: String
    let weekends: String
    let dayLabels: [Int: String]
    let holidaySuffix: String
    let skipDaysFormat: String
    /// 日本語は「祝日と1日を除く」のように、1つの形でまとめる（#197 実機レビュー）。
    let holidayAndDaysFormat: String
    /// 日本語は「1日を除く」。
    let daysOnlyFormat: String
    let isJapanese: Bool

    init(bundle: Bundle = .main, language: String? = nil) {
        func value(_ key: String) -> String {
            bundle.localizedString(forKey: key, value: nil, table: nil)
        }
        let language = language
            ?? Locale.current.language.languageCode?.identifier
            ?? bundle.preferredLocalizations.first
            ?? "en"
        isJapanese = language.hasPrefix("ja")
        never = value("never")
        everyDay = value("every_day")
        weekdays = value("weekdays")
        weekends = value("weekends")
        dayLabels = [
            1: value("day_sun"),
            2: value("day_mon"),
            3: value("day_tue"),
            4: value("day_wed"),
            5: value("day_thu"),
            6: value("day_fri"),
            7: value("day_sat"),
        ]
        holidaySuffix = value("repeat_summary_holiday_suffix")
        skipDaysFormat = value("repeat_summary_skip_days_fmt")
        holidayAndDaysFormat = value("repeat_summary_holiday_and_days_fmt")
        daysOnlyFormat = value("repeat_summary_days_only_fmt")
    }
}

/// 繰り返し行の値。休みが無ければ今までどおり、あるときは結果だけを添える（#197）。
enum RepeatSummaryLogic {
    static func text(
        weekdays: Set<Int>,
        skipsHolidays: Bool,
        skipDateCount: Int,
        strings: RepeatSummaryStrings = RepeatSummaryStrings()
    ) -> String {
        let days = weekdays.filter { (1...7).contains($0) }.sorted()
        guard !days.isEmpty else { return strings.never }

        let base: String
        if days.count == 7 {
            base = strings.everyDay
        } else if Set(days) == Set([2, 3, 4, 5, 6]) {
            base = strings.weekdays
        } else if Set(days) == Set([1, 7]) {
            base = strings.weekends
        } else {
            base = days.compactMap { strings.dayLabels[$0] }.joined(separator: " ")
        }

        var parts = [base]
        if skipsHolidays, skipDateCount > 0 {
            if strings.isJapanese {
                parts.append(String(
                    format: strings.holidayAndDaysFormat,
                    skipDateCount
                ))
            } else {
                parts.append(strings.holidaySuffix)
                parts.append(String(format: strings.skipDaysFormat, skipDateCount))
            }
        } else if skipsHolidays {
            parts.append(strings.holidaySuffix)
        } else if skipDateCount > 0 {
            let format = strings.isJapanese ? strings.daysOnlyFormat : strings.skipDaysFormat
            parts.append(String(format: format, skipDateCount))
        }
        return parts.joined(separator: "・")
    }
}

// MARK: - 「この先、鳴らない日」の結果リスト（#197 実機レビュー）

struct SkipResultDay: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case holiday(name: String)
        case picked
    }

    let dateKey: String
    let date: Date
    let kind: Kind
    let isSkipped: Bool

    var id: String { dateKey }
}

struct SkipResultYear: Identifiable, Equatable, Sendable {
    let year: Int
    let days: [SkipResultDay]

    var id: Int { year }
}

/// 祝日と選んだ日を日付順に1つにまとめる。
///
/// 同じ日は「選んだ日」を優先し、必ず鳴らない扱いにする。
enum SkipResultLogic {
    static let initialDays = 56
    static let extendedDays = 365

    static func sections(
        weekdays: Set<Int>,
        skipsHolidays: Bool,
        skipDates: Set<String>,
        holidayRingOverrides: Set<String>,
        isJapan: Bool = true,
        now: Date = Date(),
        horizonDays: Int = initialDays,
        holidays: [JapaneseHoliday] = JapaneseHolidays.all,
        calendar: Calendar = .current
    ) -> [SkipResultYear] {
        guard !weekdays.isEmpty else { return [] }
        let today = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: horizonDays, to: today) ?? today
        let todayKey = AlarmSkipLogic.dateKey(today, calendar: calendar)
        let endKey = AlarmSkipLogic.dateKey(end, calendar: calendar)

        var byKey: [String: SkipResultDay] = [:]

        if isJapan, skipsHolidays {
            for holiday in holidays {
                guard holiday.dateKey >= todayKey,
                      holiday.dateKey <= endKey,
                      let date = AlarmSkipLogic.date(
                          fromKey: holiday.dateKey,
                          calendar: calendar
                      ),
                      weekdays.contains(calendar.component(.weekday, from: date))
                else { continue }
                byKey[holiday.dateKey] = SkipResultDay(
                    dateKey: holiday.dateKey,
                    date: date,
                    kind: .holiday(name: holiday.name),
                    isSkipped: !holidayRingOverrides.contains(holiday.dateKey)
                )
            }
        }

        for key in skipDates where key >= todayKey && key <= endKey {
            guard let date = AlarmSkipLogic.date(fromKey: key, calendar: calendar),
                  weekdays.contains(calendar.component(.weekday, from: date))
            else { continue }
            // 同じ日が祝日でも、選んだ日を優先して1行にまとめる。
            byKey[key] = SkipResultDay(
                dateKey: key,
                date: date,
                kind: .picked,
                isSkipped: true
            )
        }

        let days = byKey.values.sorted { $0.date < $1.date }
        let byYear = Dictionary(grouping: days) {
            calendar.component(.year, from: $0.date)
        }
        return byYear.keys.sorted().map { year in
            SkipResultYear(
                year: year,
                days: byYear[year]!.sorted { $0.date < $1.date }
            )
        }
    }
}
