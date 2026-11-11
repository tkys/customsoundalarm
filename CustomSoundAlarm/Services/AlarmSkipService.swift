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

    /// 休みを取り消す。
    static func undo(dateKey: String) {
        var alarms = AlarmStore.shared.alarms
        var affected: Set<UUID> = []
        for index in alarms.indices where alarms[index].skipDates.contains(dateKey) {
            alarms[index].skipDates.removeAll { $0 == dateKey }
            affected.insert(alarms[index].id)
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
}
