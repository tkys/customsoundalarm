import Foundation

/// 日付でアラームを休む・祝日を除くための純ロジック（#197）。
///
/// AlarmKit の毎週くり返しには例外日を入れられないため、休む日がある曜日は
/// くり返しから外し、その曜日の直近の回を `.fixed` で別に登録する。
/// ここでは「いつ休むか」「どの曜日を外すか」「次はいつ鳴るか」だけを計算する。
enum AlarmSkipLogic {

    /// 休みの指定を反映する範囲（日）。これより先の休みは、次に同期したときに反映する。
    static let scheduleHorizonDays = 70

    /// 1曜日あたりに `.fixed` で用意する回数の上限。
    static let maxCoveragePerWeekday = 12

    /// アプリ全体で同時に登録する補完の上限（#197 レビュー）。
    /// 超えた分は近い日付から残し、次の同期に回す。
    static let maxTotalCoverage = 80

    // MARK: - 日付キー

    /// ローカル日付の `yyyy-MM-dd`。
    static func dateKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(fromKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(
            year: parts[0],
            month: parts[1],
            day: parts[2],
            hour: 0,
            minute: 0,
            second: 0
        ))
    }

    // MARK: - 休む日

    /// その日に鳴らさないか（明示の休み、または祝日で休む設定）。
    static func isSkipped(
        _ date: Date,
        entry: AlarmEntry,
        calendar: Calendar = .current
    ) -> Bool {
        let key = dateKey(date, calendar: calendar)
        if entry.skipDates.contains(key) { return true }
        guard entry.skipsHolidays, JapaneseHolidays.holiday(on: key) != nil else {
            return false
        }
        return !entry.holidayRingOverrides.contains(key)
    }

    /// `start` の日から `days` 日以内に休む日（明示＋祝日）のキー。
    static func upcomingSkipKeys(
        entry: AlarmEntry,
        from start: Date,
        days: Int = scheduleHorizonDays,
        calendar: Calendar = .current
    ) -> [String] {
        let startDay = calendar.startOfDay(for: start)
        let end = calendar.date(byAdding: .day, value: days, to: startDay) ?? startDay
        let endKey = dateKey(end, calendar: calendar)
        let startKey = dateKey(startDay, calendar: calendar)

        var keys = Set(entry.skipDates)
        if entry.skipsHolidays {
            for holiday in JapaneseHolidays.all {
                if !entry.holidayRingOverrides.contains(holiday.dateKey) {
                    keys.insert(holiday.dateKey)
                }
            }
        }
        return keys
            .filter { $0 >= startKey && $0 <= endKey }
            .sorted()
    }

    /// 休む日がある曜日を除いた、くり返しの曜日。
    static func effectiveWeekdays(
        for entry: AlarmEntry,
        after now: Date,
        horizonDays: Int = scheduleHorizonDays,
        calendar: Calendar = .current
    ) -> [Int] {
        guard !entry.repeatWeekdays.isEmpty else { return [] }
        let skippedWeekdays = skippedWeekdays(
            for: entry,
            after: now,
            horizonDays: horizonDays,
            calendar: calendar
        )
        guard !skippedWeekdays.isEmpty else { return entry.repeatWeekdays }
        return entry.repeatWeekdays.filter { !skippedWeekdays.contains($0) }
    }

    /// 休みが入っている曜日（1=日〜7=土）。
    static func skippedWeekdays(
        for entry: AlarmEntry,
        after now: Date,
        horizonDays: Int = scheduleHorizonDays,
        calendar: Calendar = .current
    ) -> Set<Int> {
        let keys = upcomingSkipKeys(entry: entry, from: now, days: horizonDays, calendar: calendar)
        let weekdays = keys.compactMap { key -> Int? in
            guard let date = date(fromKey: key, calendar: calendar) else { return nil }
            return calendar.component(.weekday, from: date)
        }
        return Set(weekdays).intersection(entry.repeatWeekdays)
    }

    // MARK: - 次に鳴る日時

    /// 休みを除いた次回の発火日時。一つも無ければ nil。
    static func nextFireDate(
        for entry: AlarmEntry,
        after referenceDate: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard entry.isEnabled, (0...23).contains(entry.hour), (0...59).contains(entry.minute) else {
            return nil
        }

        if entry.repeatWeekdays.isEmpty {
            // 一回限り。休みの日なら鳴らずに終わる。
            return rawNextFireDate(for: entry, after: referenceDate, calendar: calendar)
                .flatMap { isSkipped($0, entry: entry, calendar: calendar) ? nil : $0 }
        }

        let start = calendar.startOfDay(for: referenceDate)
        let skipKeys = Set(upcomingSkipKeys(
            entry: entry,
            from: start,
            days: 400,
            calendar: calendar
        ))
        var offset = 0
        while offset <= 400 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { break }
            offset += 1
            let weekday = calendar.component(.weekday, from: day)
            guard entry.repeatWeekdays.contains(weekday) else { continue }
            guard !skipKeys.contains(dateKey(day, calendar: calendar)) else { continue }
            guard let candidate = calendar.date(
                bySettingHour: entry.hour,
                minute: entry.minute,
                second: 0,
                of: day
            ) else { continue }
            if candidate > referenceDate { return candidate }
        }
        return nil
    }

    /// 休みを考えない次回（一回限りの日付判定に使う）。
    static func rawNextFireDate(
        for entry: AlarmEntry,
        after referenceDate: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard entry.isEnabled, (0...23).contains(entry.hour), (0...59).contains(entry.minute) else {
            return nil
        }
        if entry.repeatWeekdays.isEmpty {
            var components = DateComponents()
            components.hour = entry.hour
            components.minute = entry.minute
            components.second = 0
            return calendar.nextDate(
                after: referenceDate,
                matching: components,
                matchingPolicy: .nextTime
            )
        }
        var earliest: Date?
        for weekday in entry.repeatWeekdays where (1...7).contains(weekday) {
            var components = DateComponents()
            components.hour = entry.hour
            components.minute = entry.minute
            components.second = 0
            components.weekday = weekday
            guard let candidate = calendar.nextDate(
                after: referenceDate,
                matching: components,
                matchingPolicy: .nextTime
            ) else { continue }
            if earliest == nil || candidate < earliest! { earliest = candidate }
        }
        return earliest
    }

    /// 1回だけのアラームの次の発火日のキー。休みで止める対象かどうかの判定に使う。
    static func oneTimeOccurrenceKey(
        for entry: AlarmEntry,
        after now: Date,
        calendar: Calendar = .current
    ) -> String? {
        guard entry.repeatWeekdays.isEmpty else { return nil }
        return rawNextFireDate(for: entry, after: now, calendar: calendar)
            .map { dateKey($0, calendar: calendar) }
    }

    /// `date` に（休みを考えなければ）鳴る予定か。休みを付ける対象を決めるのに使う。
    static func fires(
        on date: Date,
        entry: AlarmEntry,
        calendar: Calendar = .current
    ) -> Bool {
        guard entry.isEnabled else { return false }
        if entry.repeatWeekdays.isEmpty {
            let start = calendar.startOfDay(for: date)
            let before = calendar.date(byAdding: .second, value: -1, to: start) ?? start
            guard let raw = rawNextFireDate(for: entry, after: before, calendar: calendar) else {
                return false
            }
            return calendar.isDate(raw, inSameDayAs: date)
        }
        return entry.repeatWeekdays.contains(calendar.component(.weekday, from: date))
    }

    /// `date` に鳴る予定のアラーム（すでに休みのものは除く）。
    static func entries(
        firingOn date: Date,
        among entries: [AlarmEntry],
        calendar: Calendar = .current
    ) -> [AlarmEntry] {
        entries.filter {
            fires(on: date, entry: $0, calendar: calendar)
                && !isSkipped(date, entry: $0, calendar: calendar)
        }
    }

    // MARK: - 曜日を外した分の補完

    /// くり返しから外した曜日に登録する `.fixed` の回。
    struct Coverage: Equatable, Sendable {
        let dateKey: String
        let date: Date
    }

    /// 外した曜日のうち、休みでない回を `.fixed` で補う。
    ///
    /// 休みの前後の通常の回も含めることで、休みの日以外は鳴る。
    /// 回数は `maxCoveragePerWeekday` で抑える（アプリを開けば次の同期で補充される）。
    static func coverageOccurrences(
        for entry: AlarmEntry,
        after referenceDate: Date,
        horizonDays: Int = scheduleHorizonDays,
        maxPerWeekday: Int = maxCoveragePerWeekday,
        calendar: Calendar = .current
    ) -> [Coverage] {
        guard entry.isEnabled, !entry.repeatWeekdays.isEmpty else { return [] }

        let start = calendar.startOfDay(for: referenceDate)
        let skipKeys = Set(upcomingSkipKeys(
            entry: entry,
            from: start,
            days: horizonDays,
            calendar: calendar
        ))
        let effective = effectiveWeekdays(
            for: entry,
            after: referenceDate,
            horizonDays: horizonDays,
            calendar: calendar
        )
        let removed = skippedWeekdays(
            for: entry,
            after: referenceDate,
            horizonDays: horizonDays,
            calendar: calendar
        )

        // 全曜日を外す場合（年末年始など）は、本体を最初の1回だけ `.fixed` にし、
        // 残りの70日分をここで補完する。1回だけ登録して終わりにしない（#197 レビュー）。
        let allWeekdaysRemoved = effective.isEmpty
        let weekdaysToCover: Set<Int>
        if allWeekdaysRemoved {
            weekdaysToCover = Set(entry.repeatWeekdays)
        } else {
            guard !removed.isEmpty else { return [] }
            weekdaysToCover = removed
        }

        var result: [Coverage] = []
        var perWeekday: [Int: Int] = [:]
        var offset = 0
        while offset <= horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { break }
            offset += 1
            let weekday = calendar.component(.weekday, from: day)
            guard weekdaysToCover.contains(weekday) else { continue }
            let key = dateKey(day, calendar: calendar)
            guard !skipKeys.contains(key) else { continue }
            guard let candidate = calendar.date(
                bySettingHour: entry.hour,
                minute: entry.minute,
                second: 0,
                of: day
            ), candidate > referenceDate else { continue }
            let count = perWeekday[weekday, default: 0]
            guard count < maxPerWeekday else { continue }
            perWeekday[weekday] = count + 1
            result.append(Coverage(dateKey: key, date: candidate))
        }
        if allWeekdaysRemoved, !result.isEmpty {
            // 最初の1回は本体（.fixed）が受け持つ
            result.removeFirst()
        }
        return result
    }

    /// 補完の1件（アプリ全体の上限を決めるために entryID と組にする）。
    struct CoverageItem: Equatable, Sendable {
        let entryID: UUID
        let coverage: Coverage
    }

    /// 近い日付から `limit` 件だけ残す。超えた分は次の同期に回す（#197 レビュー）。
    static func limitedCoverage(
        _ items: [CoverageItem],
        limit: Int = maxTotalCoverage
    ) -> (selected: [CoverageItem], deferred: Int) {
        let sorted = items.sorted { $0.coverage.date < $1.coverage.date }
        return (Array(sorted.prefix(limit)), max(0, sorted.count - limit))
    }

    /// 祝日・休みの設定があるアラームを止めたとき、日付が変わった最初の停止で
    /// 軽く同期する（#197 レビュー）。
    static func shouldReconcileOnStop(
        entry: AlarmEntry,
        lastDay: String?,
        today: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard entry.skipsHolidays || !entry.skipDates.isEmpty else { return false }
        return lastDay != dateKey(today, calendar: calendar)
    }

    /// 全曜日を外すほど休みが続くとき、本体を次の1回だけ `.fixed` で登録する。
    static func primaryUsesFixed(
        for entry: AlarmEntry,
        after now: Date,
        horizonDays: Int = scheduleHorizonDays,
        calendar: Calendar = .current
    ) -> Bool {
        !entry.repeatWeekdays.isEmpty
            && effectiveWeekdays(
                for: entry,
                after: now,
                horizonDays: horizonDays,
                calendar: calendar
            ).isEmpty
    }

    // MARK: - 一覧のまとめ

    /// 次に鳴る日ごとのまとまり。
    struct DayGroup: Identifiable, Equatable, Sendable {
        let dateKey: String
        let date: Date
        let entries: [AlarmEntry]

        var id: String { dateKey }

        var oneTimeCount: Int {
            entries.filter { $0.repeatWeekdays.isEmpty }.count
        }
    }

    static func upcomingDayGroups(
        entries: [AlarmEntry],
        after now: Date,
        limit: Int = 1,
        calendar: Calendar = .current
    ) -> [DayGroup] {
        var byDay: [String: (date: Date, entries: [AlarmEntry])] = [:]
        for entry in entries where entry.isEnabled {
            guard let next = entry.nextFireDate(from: now, calendar: calendar) else { continue }
            let key = dateKey(next, calendar: calendar)
            let day = calendar.startOfDay(for: next)
            var group = byDay[key] ?? (day, [])
            group.entries.append(entry)
            byDay[key] = group
        }
        return byDay.values
            .sorted { $0.date < $1.date }
            .prefix(limit)
            .map { DayGroup(
                dateKey: dateKey($0.date, calendar: calendar),
                date: $0.date,
                entries: $0.entries.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
            ) }
    }

    /// 休みにした日の案内（その日が終わるまで表示する）。
    struct Notice: Equatable, Sendable {
        let dateKey: String
        let date: Date
        let nextFire: Date?
    }

    /// いま表示すべき休みの案内。今日以降で最も近い、明示の休みの日。
    static func activeNotice(
        entries: [AlarmEntry],
        now: Date,
        calendar: Calendar = .current
    ) -> Notice? {
        let todayKey = dateKey(calendar.startOfDay(for: now), calendar: calendar)
        var skipped: [String: [AlarmEntry]] = [:]
        for entry in entries {
            var keys = entry.skipDates
            if let disabled = entry.skipDisabledDate {
                keys.append(disabled)
            }
            for key in keys where key >= todayKey {
                skipped[key, default: []].append(entry)
            }
        }
        guard let key = skipped.keys.min(),
              let date = date(fromKey: key, calendar: calendar) else {
            return nil
        }
        let affected = skipped[key] ?? []
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
            ?? date
        let nextFire = affected.compactMap {
            nextFireDate(for: $0, after: endOfDay, calendar: calendar)
        }.min()
        return Notice(dateKey: key, date: date, nextFire: nextFire)
    }

    // MARK: - 祝日

    /// 次に休む祝日（休む設定があり、その曜日がくり返しに入っているもの）。
    static func nextSkippedHoliday(
        for entry: AlarmEntry,
        after now: Date,
        calendar: Calendar = .current
    ) -> JapaneseHoliday? {
        guard entry.skipsHolidays else { return nil }
        return nextSkippedHoliday(
            forWeekdays: entry.repeatWeekdays,
            overrides: Set(entry.holidayRingOverrides),
            after: now,
            calendar: calendar
        )
    }

    static func nextSkippedHoliday(
        forWeekdays weekdays: [Int],
        overrides: Set<String>,
        after now: Date,
        calendar: Calendar = .current
    ) -> JapaneseHoliday? {
        guard !weekdays.isEmpty else { return nil }
        let start = calendar.startOfDay(for: now)
        let startKey = dateKey(start, calendar: calendar)
        return JapaneseHolidays.all
            .filter { $0.dateKey >= startKey }
            .filter { !overrides.contains($0.dateKey) }
            .first { holiday in
                guard let date = date(fromKey: holiday.dateKey, calendar: calendar) else {
                    return false
                }
                return weekdays.contains(calendar.component(.weekday, from: date))
            }
    }

    /// 端末の地域が日本か（祝日の設定を出す条件）。
    static func isJapanRegion(locale: Locale = .current) -> Bool {
        locale.region?.identifier == "JP"
    }

    // MARK: - 後片付け

    /// 過ぎた休み・祝日の上書きを落とす。
    static func pruning(
        _ entry: AlarmEntry,
        now: Date,
        calendar: Calendar = .current
    ) -> AlarmEntry {
        let todayKey = dateKey(calendar.startOfDay(for: now), calendar: calendar)
        var copy = entry
        copy.skipDates = entry.skipDates.filter { $0 >= todayKey }.sorted()
        copy.holidayRingOverrides = entry.holidayRingOverrides
            .filter { $0 >= todayKey }
            .sorted()
        return copy
    }
}
