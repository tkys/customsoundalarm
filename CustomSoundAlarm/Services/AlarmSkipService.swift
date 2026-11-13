import Foundation

/// 休みの指定方法（計測・AppIntent で共用・#197）。
enum AlarmSkipScope: String, Sendable, CaseIterable {
    /// 次に鳴る日をまとめて休む
    case day
    /// その日のアラームから選んで休む
    case selected
    /// 期間を選んで休む
    case range
}

/// 休み・祝日設定の適用（#197）。
///
/// UI と AppIntent の両方から同じ処理を呼べるようにする。
/// 適用後は必ず同期し、AlarmKit のくり返しと補完を作り直す。
@MainActor
enum AlarmSkipService {

    /// 指定したアラームを、指定した日付だけ休む。
    ///
    /// くり返しのアラームは `skipDates` に日付を足す。
    /// 1回だけのアラームは休みの翌日に鳴らないよう、その場でオフにする
    /// （`skipDisabledDate` に日付を残し、「取り消す」で戻せる）。
    /// - Returns: 実際に変わったアラーム数
    @discardableResult
    static func skip(
        entryIDs: Set<UUID>,
        dateKeys: Set<String>,
        scope: AlarmSkipScope,
        trigger: AlarmSyncTrigger = .edit
    ) -> Int {
        guard !entryIDs.isEmpty, !dateKeys.isEmpty else { return 0 }
        var alarms = AlarmStore.shared.alarms.map {
            AlarmSkipLogic.pruning($0, now: Date())
        }
        var affected: Set<UUID> = []
        for index in alarms.indices {
            guard entryIDs.contains(alarms[index].id) else { continue }

            if alarms[index].repeatWeekdays.isEmpty {
                guard let occurrence = AlarmSkipLogic.oneTimeOccurrenceKey(
                    for: alarms[index],
                    after: Date()
                ), dateKeys.contains(occurrence) else { continue }
                guard alarms[index].isEnabled
                    || alarms[index].skipDisabledDate != occurrence else { continue }
                alarms[index].isEnabled = false
                alarms[index].skipDisabledDate = occurrence
                affected.insert(alarms[index].id)
                continue
            }

            let merged = Set(alarms[index].skipDates).union(dateKeys)
            guard merged.count != alarms[index].skipDates.count else { continue }
            alarms[index].skipDates = merged.sorted()
            affected.insert(alarms[index].id)
        }
        guard !affected.isEmpty else { return 0 }
        AlarmStore.shared.replaceAll(alarms)
        AlarmScheduler.shared.syncAlarms(
            alarms,
            forceRescheduleEntryIDs: affected,
            trigger: trigger
        )
        AnalyticsService.shared.capture(.alarmSkipSet(
            scope: scope,
            days: dateKeys.count,
            alarmCount: affected.count
        ))
        return affected.count
    }

    /// 次に鳴る日をまとめて休む。
    static func skipDay(_ date: Date, entries: [AlarmEntry]) {
        skip(
            entryIDs: Set(entries.map(\.id)),
            dateKeys: [AlarmSkipLogic.dateKey(date)],
            scope: .day
        )
    }

    /// その日のアラームから選んで休む（選ばれたものだけ）。
    static func skipSelected(_ entryIDs: Set<UUID>, date: Date) {
        skip(
            entryIDs: entryIDs,
            dateKeys: [AlarmSkipLogic.dateKey(date)],
            scope: .selected
        )
    }

    /// 期間内に鳴るアラームを休む。
    static func skipRange(from: Date, to: Date, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: min(from, to))
        let end = calendar.startOfDay(for: max(from, to))
        let entries = AlarmStore.shared.alarms
        var byEntry: [UUID: Set<String>] = [:]
        var dayCount = 0
        var day = start
        while day <= end {
            let key = AlarmSkipLogic.dateKey(day, calendar: calendar)
            for entry in entries where entry.isEnabled
                && AlarmSkipLogic.fires(on: day, entry: entry, calendar: calendar) {
                byEntry[entry.id, default: []].insert(key)
            }
            dayCount += 1
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        guard !byEntry.isEmpty else { return }

        var alarms = entries.map { AlarmSkipLogic.pruning($0, now: Date()) }
        var affected: Set<UUID> = []
        for index in alarms.indices {
            guard let keys = byEntry[alarms[index].id], !keys.isEmpty else { continue }

            if alarms[index].repeatWeekdays.isEmpty {
                guard let key = keys.sorted().first else { continue }
                guard alarms[index].isEnabled
                    || alarms[index].skipDisabledDate != key else { continue }
                alarms[index].isEnabled = false
                alarms[index].skipDisabledDate = key
                affected.insert(alarms[index].id)
                continue
            }

            let merged = Set(alarms[index].skipDates).union(keys)
            if merged.count != alarms[index].skipDates.count {
                affected.insert(alarms[index].id)
            }
            alarms[index].skipDates = merged.sorted()
        }
        guard !affected.isEmpty else { return }
        AlarmStore.shared.replaceAll(alarms)
        AlarmScheduler.shared.syncAlarms(
            alarms,
            forceRescheduleEntryIDs: affected,
            trigger: .edit
        )
        AnalyticsService.shared.capture(.alarmSkipSet(
            scope: .range,
            days: dayCount,
            alarmCount: affected.count
        ))
    }

    /// 休みを取り消す。1回だけのアラームはオンに戻す。
    static func undo(dateKey: String) {
        undo(entryIDs: Set(AlarmStore.shared.alarms.map(\.id)), dateKey: dateKey)
    }

    /// 指定したアラームの休みだけを取り消す（#197 画面作り直し）。
    static func undo(entryIDs: Set<UUID>, dateKey: String) {
        var alarms = AlarmStore.shared.alarms
        var affected: Set<UUID> = []
        for index in alarms.indices where entryIDs.contains(alarms[index].id) {
            var changed = false
            if alarms[index].skipDates.contains(dateKey) {
                alarms[index].skipDates.removeAll { $0 == dateKey }
                changed = true
            }
            if alarms[index].skipDisabledDate == dateKey {
                alarms[index].isEnabled = true
                alarms[index].skipDisabledDate = nil
                changed = true
            }
            if changed {
                affected.insert(alarms[index].id)
            }
        }
        guard !affected.isEmpty else { return }
        AlarmStore.shared.replaceAll(alarms)
        AlarmScheduler.shared.syncAlarms(
            alarms,
            forceRescheduleEntryIDs: affected,
            trigger: .edit
        )
        AnalyticsService.shared.capture(.alarmSkipUndone)
    }

    // MARK: - すべてのアラームを休む（#197 画面作り直し）

    /// プリセット（24時間 / 3日間 / 7日間）で、いまオンのアラームをまとめて休む。
    /// - Returns: 休みに入れたアラーム数（同時に鳴らなくなる回数ではない）
    @discardableResult
    static func skipAll(preset: AlarmSkipLogic.GlobalSkipPreset) -> Int {
        guard let interval = AlarmSkipLogic.presetInterval(preset, from: Date()) else {
            return 0
        }
        return applyGlobalSkip(interval: interval, preset: preset.rawValue)
    }

    /// 開始日〜終了日で、いまオンのアラームをまとめて休む。
    @discardableResult
    static func skipAll(startDay: Date, endDay: Date) -> Int {
        guard let interval = AlarmSkipLogic.customInterval(
            startDay: startDay,
            endDay: endDay
        ) else { return 0 }
        return applyGlobalSkip(interval: interval, preset: "custom")
    }

    private static func applyGlobalSkip(
        interval: DateInterval,
        preset: String
    ) -> Int {
        let now = Date()
        let todayKey = AlarmSkipLogic.dateKey(now)
        var alarms = AlarmStore.shared.alarms.map {
            AlarmSkipLogic.pruning($0, now: now)
        }

        // 前の全体の休みで止めた1回きりのアラームを、新しい休みの判定に載せ直す。
        // すでに予定時刻が過ぎたものは、鳴らずに終わったままにする（#197）。
        if let previous = AppGroup.globalSkip {
            let previousDisabled = Set(previous.disabledOneTimeIDs)
            for index in alarms.indices
            where previousDisabled.contains(alarms[index].id) && !alarms[index].isEnabled {
                if let marker = alarms[index].skipDisabledDate, marker >= todayKey {
                    alarms[index].isEnabled = true
                    alarms[index].skipDisabledDate = nil
                } else {
                    alarms[index].skipDisabledDate = nil
                }
            }
        }

        let targetIDs = Set(alarms.filter(\.isEnabled).map(\.id))
        guard !targetIDs.isEmpty else { return 0 }

        let silencedIDs = Set(alarms.filter { alarm in
            targetIDs.contains(alarm.id)
                && !AlarmSkipLogic.occurrences(of: alarm, in: interval).isEmpty
        }.map(\.id))

        var disabledOneTimeIDs: [UUID] = []
        for index in alarms.indices where targetIDs.contains(alarms[index].id) {
            guard alarms[index].repeatWeekdays.isEmpty else { continue }
            guard let occurrence = AlarmSkipLogic.occurrences(
                of: alarms[index],
                in: interval
            ).first else { continue }
            alarms[index].isEnabled = false
            alarms[index].skipDisabledDate = AlarmSkipLogic.dateKey(occurrence)
            disabledOneTimeIDs.append(alarms[index].id)
        }

        AppGroup.globalSkip = GlobalSkip(
            start: interval.start,
            end: interval.end,
            entryIDs: Array(targetIDs),
            disabledOneTimeIDs: disabledOneTimeIDs
        )
        AlarmStore.shared.replaceAll(alarms)
        AlarmScheduler.shared.syncAlarms(
            alarms,
            forceRescheduleEntryIDs: targetIDs,
            trigger: .edit
        )
        AnalyticsService.shared.capture(.skipAllSet(
            preset: preset,
            alarmCount: silencedIDs.count
        ))
        return targetIDs.count
    }

    /// 全体の休みを取り消す。個別の休みは残す。
    static func undoAll() {
        guard let skip = AppGroup.globalSkip else { return }
        let now = Date()
        var alarms = AlarmStore.shared.alarms.map {
            AlarmSkipLogic.pruning($0, now: now)
        }
        let disabled = Set(skip.disabledOneTimeIDs)
        let todayKey = AlarmSkipLogic.dateKey(now)
        var affected = skippedEntryIDs(in: alarms, skip: skip)
        for index in alarms.indices where disabled.contains(alarms[index].id) {
            guard !alarms[index].isEnabled,
                  let marker = alarms[index].skipDisabledDate else { continue }
            if marker >= todayKey {
                alarms[index].isEnabled = true
            }
            alarms[index].skipDisabledDate = nil
            affected.insert(alarms[index].id)
        }
        AppGroup.globalSkip = nil
        AlarmStore.shared.replaceAll(alarms)
        AlarmScheduler.shared.syncAlarms(
            alarms,
            forceRescheduleEntryIDs: affected.union(skip.entryIDs),
            trigger: .edit
        )
        AnalyticsService.shared.capture(.skipAllUndone)
    }

    private static func skippedEntryIDs(
        in alarms: [AlarmEntry],
        skip: GlobalSkip
    ) -> Set<UUID> {
        Set(alarms.map(\.id)).intersection(skip.entryIDs)
    }

    // MARK: - 1本だけ次の1回を休む

    /// 繰り返しのアラームの、次に鳴る日を休む。
    @discardableResult
    static func skipNext(entryID: UUID) -> Bool {
        guard let entry = AlarmStore.shared.alarms.first(where: { $0.id == entryID }),
              !entry.repeatWeekdays.isEmpty,
              let next = AlarmSkipLogic.nextFireDate(for: entry, after: Date())
        else { return false }
        let key = AlarmSkipLogic.dateKey(next)
        skip(entryIDs: [entryID], dateKeys: [key], scope: .day)
        return true
    }

    /// 繰り返しのアラームの、いちばん近い休みを取り消す。
    @discardableResult
    static func undoNext(entryID: UUID) -> Bool {
        guard let entry = AlarmStore.shared.alarms.first(where: { $0.id == entryID }),
              !entry.repeatWeekdays.isEmpty,
              let skipped = AlarmSkipLogic.nextIndividualSkipDate(
                  for: entry,
                  after: Date()
              )
        else { return false }
        undo(entryIDs: [entryID], dateKey: AlarmSkipLogic.dateKey(skipped))
        return true
    }
}
