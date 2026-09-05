import Foundation
import AlarmKit
import SwiftUI
import os

// MARK: - AlarmScheduler

@Observable
@MainActor
final class AlarmScheduler {
    static let shared = AlarmScheduler()

    private let logger = Logger(subsystem: "com.tkysdev.customsoundalarm", category: "AlarmScheduler")
    private nonisolated(unsafe) let manager = AlarmManager.shared

    private(set) var scheduledAlarmCount: Int = 0

    /// AlarmEntry.id → AlarmKit Alarm.ID のマッピング
    private var alarmIDMap: [UUID: Alarm.ID] = [:]

    /// sync の直列化用（連続操作時に前回をキャンセルして最新のみ実行）
    private var syncTask: Task<Void, Never>?

    /// 状態監視タスク（重複防止用にハンドル保持）
    private var observationTask: Task<Void, Never>?

    /// ID マッピングの永続化キー
    private let idMapKey = "alarm_id_map"

    /// 同一 AlarmEntry.ID に対して alarm_fired を1回だけ送るための記録（observer 系）
    @ObservationIgnored
    private var firedReportedThisSession: Set<Alarm.ID> = []

    private init() {
        loadIDMap()
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        switch manager.authorizationState {
        case .notDetermined:
            do {
                let state = try await manager.requestAuthorization()
                if state == .authorized {
                    recordPermissionStatus(.authorized)
                    return true
                } else {
                    recordPermissionStatus(.denied)
                    return false
                }
            } catch {
                logger.error("AlarmKit authorization failed: \(error.localizedDescription)")
                recordPermissionStatus(.requestFailed)
                return false
            }
        case .authorized:
            recordPermissionStatus(.authorized)
            return true
        case .denied:
            recordPermissionStatus(.denied)
            return false
        @unknown default:
            recordPermissionStatus(.unknown)
            return false
        }
    }

    /// 権限状態を計測する（#91-2）。
    /// **前回送信時と状態が変わったときだけ**送る（状態を永続化して比較）。
    /// 従来はセッション内メモリ比較だったため実質起動ごとに送信され、
    /// 6.8回/人を消費していた。判定は `AnalyticsThrottle`（純粋関数）。
    private func recordPermissionStatus(_ status: AlarmPermissionStatus) {
        let lastSent = AppGroup.lastReportedPermissionStatus
            .flatMap { AlarmPermissionStatus(rawValue: $0) }
        guard AnalyticsThrottle.shouldSendPermissionStatus(current: status, lastSent: lastSent) else { return }
        AppGroup.lastReportedPermissionStatus = status.rawValue
        AnalyticsService.shared.capture(.alarmPermission(status: status))
    }

    // MARK: - Reconciliation (起動時の整合性チェック)

    /// アプリ起動時に AlarmKit の状態と AlarmStore を突合し、
    /// 発火済みの一回限りアラームを自動 OFF にする
    func reconcileOnLaunch() {
        let activeAlarmIDs: Set<Alarm.ID>
        do {
            activeAlarmIDs = Set(try manager.alarms.map(\.id))
        } catch {
            logger.error("Failed to fetch alarms for reconciliation: \(error.localizedDescription)")
            return
        }

        let store = AlarmStore.shared
        var didChange = false

        for alarm in store.alarms where alarm.isEnabled && alarm.repeatWeekdays.isEmpty {
            if let mappedID = alarmIDMap[alarm.id], !activeAlarmIDs.contains(mappedID) {
                // 発火済みの一回限りアラーム → 遡及記録してから無効化
                AnalyticsService.shared.capture(.alarmFired(
                    wasAppForeground: false,
                    hour: alarm.hour,
                    isRepeating: false,
                    detection: "reconcile"
                ))
                store.toggleEnabled(alarm)
                alarmIDMap.removeValue(forKey: alarm.id)
                didChange = true
                logger.info("Reconcile: one-time alarm auto-disabled: \(alarm.label)")
            }
        }

        if didChange {
            saveIDMap()
        }

        // スヌーズ待機中（.countdown）のアラームを遡及記録（App Group 永続化で二重計上防止）
        var snoozedIDs = AppGroup.snoozedAlarmEntryIDs
        for alarm in (try? manager.alarms) ?? [] where alarm.state == .countdown {
            guard let entryID = alarmIDMap.first(where: { $0.value == alarm.id })?.key,
                  !snoozedIDs.contains(entryID)
            else { continue }
            snoozedIDs.insert(entryID)
            AnalyticsService.shared.capture(.alarmSnoozed(from: "reconcile"))
            logger.info("Reconcile: detected snoozing alarm: \(alarm.id)")
        }
        // .countdown でなくなったアラームをクリーンアップ
        let currentCountdownEntryIDs = Set(((try? manager.alarms) ?? []).compactMap { alarm in
            alarm.state == .countdown
                ? alarmIDMap.first(where: { $0.value == alarm.id })?.key
                : nil
        })
        snoozedIDs.formIntersection(currentCountdownEntryIDs)
        AppGroup.snoozedAlarmEntryIDs = snoozedIDs
    }

    // MARK: - Scheduling

    /// 全アラームを同期（直列化: 連続呼び出し時は前回をキャンセルし最新のみ実行）
    func syncAlarms(_ entries: [AlarmEntry]) {
        syncTask?.cancel()
        syncTask = Task {
            await performSync(entries)
        }
    }

    private func performSync(_ entries: [AlarmEntry]) async {
        guard !Task.isCancelled else { return }

        guard await requestAuthorization() else {
            logger.warning("AlarmKit not authorized, skipping alarm sync")
            return
        }

        let activeStates: [Alarm.ID: Alarm.State]
        do {
            activeStates = Dictionary(uniqueKeysWithValues: try manager.alarms.map { ($0.id, $0.state) })
        } catch {
            logger.error("Failed to fetch alarm states: \(error.localizedDescription)")
            return
        }

        let diff = computeSyncDiff(
            oldMap: alarmIDMap,
            entries: entries,
            activeStates: activeStates
        )

        // Cancel alarms for disabled/deleted entries
        for entryID in diff.cancelEntryIDs {
            guard let alarmID = alarmIDMap[entryID] else { continue }
            do {
                try manager.cancel(id: alarmID)
                logger.info("Cancelled alarm for removed entry: \(entryID)")
            } catch {
                logger.error("Failed to cancel alarm \(alarmID): \(error.localizedDescription)")
            }
        }

        // Cancel old alarms for entries being rescheduled (before scheduling new ones)
        for (_, oldAlarmID) in diff.rescheduleAlarmIDs {
            do {
                try manager.cancel(id: oldAlarmID)
                logger.info("Cancelled old alarm for reschedule: \(oldAlarmID)")
            } catch {
                logger.error("Failed to cancel old alarm \(oldAlarmID): \(error.localizedDescription)")
            }
        }

        // Schedule new/changed entries
        var newMap = diff.keptMap
        for entry in diff.scheduleEntries {
            guard !Task.isCancelled else { return }
            if let alarmID = await scheduleAlarm(for: entry) {
                newMap[entry.id] = alarmID
            }
        }

        guard !Task.isCancelled else { return }

        alarmIDMap = newMap
        scheduledAlarmCount = newMap.count
        saveIDMap()

        logger.info("Synced \(self.scheduledAlarmCount) alarms (\(diff.keptMap.count) kept, \(diff.scheduleEntries.count) scheduled, \(diff.cancelEntryIDs.count) cancelled, \(diff.rescheduleAlarmIDs.count) rescheduled)")
    }

    /// 単一アラームをスケジュール（成功時に Alarm.ID を返す）
    private func scheduleAlarm(for entry: AlarmEntry) async -> Alarm.ID? {
        let displayName = SoundStore.shared.displayName(for: entry.soundFileName)
        let metadata = CustomAlarmMetadata(entry: entry, soundDisplayName: displayName)

        let hasSnooze = entry.snoozeMinutes > 0

        let alert: AlarmPresentation.Alert
        if hasSnooze {
            if #available(iOS 26.1, *) {
                alert = AlarmPresentation.Alert(
                    title: LocalizedStringResource(stringLiteral: entry.label),
                    secondaryButton: AlarmButton(
                        text: "snooze",
                        textColor: .blue,
                        systemImageName: "clock.fill"
                    ),
                    secondaryButtonBehavior: .countdown
                )
            } else {
                alert = AlarmPresentation.Alert(
                    title: LocalizedStringResource(stringLiteral: entry.label),
                    stopButton: AlarmButton(
                        text: "stop_alarm",
                        textColor: .red,
                        systemImageName: "stop.fill"
                    ),
                    secondaryButton: AlarmButton(
                        text: "snooze",
                        textColor: .blue,
                        systemImageName: "clock.fill"
                    ),
                    secondaryButtonBehavior: .countdown
                )
            }
        } else {
            if #available(iOS 26.1, *) {
                alert = AlarmPresentation.Alert(
                    title: LocalizedStringResource(stringLiteral: entry.label)
                )
            } else {
                alert = AlarmPresentation.Alert(
                    title: LocalizedStringResource(stringLiteral: entry.label),
                    stopButton: AlarmButton(
                        text: "stop_alarm",
                        textColor: .red,
                        systemImageName: "stop.fill"
                    )
                )
            }
        }

        let countdownPresentation: AlarmPresentation.Countdown?
        if hasSnooze {
            countdownPresentation = AlarmPresentation.Countdown(
                title: LocalizedStringResource(stringLiteral: entry.label),
                pauseButton: nil
            )
        } else {
            countdownPresentation = nil
        }

        let attributes = AlarmAttributes<CustomAlarmMetadata>(
            presentation: AlarmPresentation(
                alert: alert,
                countdown: countdownPresentation,
                paused: nil
            ),
            metadata: metadata,
            tintColor: .orange
        )

        let alarmTime = Alarm.Schedule.Relative.Time(
            hour: entry.hour,
            minute: entry.minute
        )

        let schedule: Alarm.Schedule
        if entry.repeatWeekdays.isEmpty {
            schedule = .relative(.init(time: alarmTime, repeats: .never))
        } else {
            let weekdays = entry.repeatWeekdays.compactMap { dayInt -> Locale.Weekday? in
                switch dayInt {
                case 1: .sunday
                case 2: .monday
                case 3: .tuesday
                case 4: .wednesday
                case 5: .thursday
                case 6: .friday
                case 7: .saturday
                default: nil
                }
            }
            let recurrence = Alarm.Schedule.Relative.Recurrence.weekly(weekdays)
            schedule = .relative(.init(time: alarmTime, repeats: recurrence))
        }

        let countdownDuration: Alarm.CountdownDuration?
        if hasSnooze {
            #if DEBUG
            let useSeconds = UserDefaults.standard.bool(forKey: "SnoozeDebugUseSeconds")
            #else
            let useSeconds = false
            #endif
            countdownDuration = Alarm.CountdownDuration(
                preAlert: nil,
                postAlert: snoozeInterval(minutes: entry.snoozeMinutes, useSeconds: useSeconds)
            )
        } else {
            countdownDuration = nil
        }

        let config = AlarmManager.AlarmConfiguration<CustomAlarmMetadata>(
            countdownDuration: countdownDuration,
            schedule: schedule,
            attributes: attributes,
            stopIntent: DismissAlarmIntent(),
            sound: entry.soundFileName.isEmpty ? .default : .named(entry.soundFileName)
        )

        do {
            let alarmID = Alarm.ID()
            _ = try await manager.schedule(id: alarmID, configuration: config)
            logger.info("Scheduled alarm: \(entry.timeString) - \(entry.label)")
            return alarmID
        } catch {
            logger.error("Failed to schedule alarm \(entry.label): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Alarm State Observation

    /// アラーム状態の監視を開始（重複呼び出し時は前回をキャンセル）
    func startObservingAlarmStates() {
        observationTask?.cancel()
        observationTask = Task {
            for await alarms in manager.alarmUpdates {
                guard !Task.isCancelled else { break }
                for alarm in alarms {
                    switch alarm.state {
                    case .alerting:
                        logger.info("Alarm alerting: \(alarm.id)")
                        handleAlarmFired(alarmKitID: alarm.id)
                    case .countdown:
                        // スヌーズ待機中への遷移を検知（App Group 永続化で二重計上防止）
                        guard let entryID = alarmIDMap.first(where: { $0.value == alarm.id })?.key else { continue }
                        var snoozedIDs = AppGroup.snoozedAlarmEntryIDs
                        guard !snoozedIDs.contains(entryID) else { continue }
                        snoozedIDs.insert(entryID)
                        AppGroup.snoozedAlarmEntryIDs = snoozedIDs
                        logger.info("Alarm snoozed: \(alarm.id)")
                        AnalyticsService.shared.capture(.alarmSnoozed(from: "observer"))
                    default:
                        // スヌーズ解除の検知: .countdown でなくなったアラームをクリーンアップ
                        guard let entryID = alarmIDMap.first(where: { $0.value == alarm.id })?.key else { continue }
                        var snoozedIDs = AppGroup.snoozedAlarmEntryIDs
                        if snoozedIDs.remove(entryID) != nil {
                            AppGroup.snoozedAlarmEntryIDs = snoozedIDs
                        }
                    }
                }
            }
        }
    }

    /// 一回限りアラーム発火後に isEnabled を false にする
    private func handleAlarmFired(alarmKitID: Alarm.ID) {
        // 定着ユーザー判定用に発火実績を記録（同一日は1回、鳴動中は毎tick呼ばれるが日単位で冪等）
        // マッピング欠落時（オーファン）でも呼び出す
        ReviewRequestManager.shared.recordAlarmFired()

        guard let entryID = alarmIDMap.first(where: { $0.value == alarmKitID })?.key else {
            return
        }

        let store = AlarmStore.shared
        guard let alarm = store.alarms.first(where: { $0.id == entryID }) else {
            return
        }

        // alarm_fired 計測（同一 Alarm.ID につきセッション中1回のみ）
        if !firedReportedThisSession.contains(alarmKitID) {
            firedReportedThisSession.insert(alarmKitID)
            AnalyticsService.shared.capture(.alarmFired(
                wasAppForeground: true,
                hour: alarm.hour,
                isRepeating: !alarm.repeatWeekdays.isEmpty,
                detection: "observer"
            ))
        }

        if alarm.repeatWeekdays.isEmpty && alarm.isEnabled {
            store.toggleEnabled(alarm)
            alarmIDMap.removeValue(forKey: entryID)
            saveIDMap()
            logger.info("One-time alarm fired, auto-disabled: \(alarm.label)")
        }
    }

    // MARK: - ID Map Persistence

    private func saveIDMap() {
        do {
            let data = try JSONEncoder().encode(alarmIDMap)
            AppGroup.userDefaults.set(data, forKey: idMapKey)
        } catch {
            logger.error("Failed to save alarm ID map: \(error.localizedDescription)")
        }
    }

    private func loadIDMap() {
        guard let data = AppGroup.userDefaults.data(forKey: idMapKey) else { return }
        do {
            alarmIDMap = try JSONDecoder().decode([UUID: Alarm.ID].self, from: data)
            logger.info("Loaded alarm ID map with \(self.alarmIDMap.count) entries")
        } catch {
            logger.warning("Failed to decode alarm ID map, starting fresh")
            alarmIDMap = [:]
        }
    }
}

// MARK: - SyncDiff

/// 差分同期のための計算結果。`computeSyncDiff` が返す。
struct SyncDiff: Sendable {
    /// 保護状態のためマップに残す entryID → Alarm.ID
    var keptMap: [UUID: Alarm.ID]
    /// 削除/無効化されたためキャンセルが必要な entryID
    var cancelEntryIDs: Set<UUID>
    /// 再スケジュール前にキャンセルすべき旧 Alarm（scheduleEntries のうち oldMap に存在したもの）
    var rescheduleAlarmIDs: [UUID: Alarm.ID]
    /// 新規または変更があったためスケジュールが必要な AlarmEntry
    var scheduleEntries: [AlarmEntry]
}

/// 差分同期のための alarmIDMap 遷移を計算する純粋関数。
/// 副作用がなく、単体テスト可能。
func computeSyncDiff(
    oldMap: [UUID: Alarm.ID],
    entries: [AlarmEntry],
    activeStates: [Alarm.ID: Alarm.State]
) -> SyncDiff {
    let enabledEntryIDs = Set(entries.filter(\.isEnabled).map(\.id))
    var keptMap: [UUID: Alarm.ID] = [:]
    var cancelEntryIDs = Set<UUID>()
    var rescheduleAlarmIDs: [UUID: Alarm.ID] = [:]
    var scheduleEntries: [AlarmEntry] = []

    for entryID in oldMap.keys where !enabledEntryIDs.contains(entryID) {
        cancelEntryIDs.insert(entryID)
    }

    for entry in entries where entry.isEnabled {
        if let alarmID = oldMap[entry.id],
           let state = activeStates[alarmID],
           state == .countdown || state == .alerting || state == .paused {
            keptMap[entry.id] = alarmID
        } else {
            if let oldAlarmID = oldMap[entry.id] {
                rescheduleAlarmIDs[entry.id] = oldAlarmID
            }
            scheduleEntries.append(entry)
        }
    }

    return SyncDiff(
        keptMap: keptMap,
        cancelEntryIDs: cancelEntryIDs,
        rescheduleAlarmIDs: rescheduleAlarmIDs,
        scheduleEntries: scheduleEntries
    )
}
