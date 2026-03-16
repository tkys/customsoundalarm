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

    private init() {
        loadIDMap()
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        switch manager.authorizationState {
        case .notDetermined:
            do {
                let state = try await manager.requestAuthorization()
                return state == .authorized
            } catch {
                logger.error("AlarmKit authorization failed: \(error.localizedDescription)")
                return false
            }
        case .authorized:
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
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
            // 一回限りアラームが enabled なのに AlarmKit にない → 発火済み
            if let mappedID = alarmIDMap[alarm.id], !activeAlarmIDs.contains(mappedID) {
                store.toggleEnabled(alarm)
                alarmIDMap.removeValue(forKey: alarm.id)
                didChange = true
                logger.info("Reconcile: one-time alarm auto-disabled: \(alarm.label)")
            }
            // マッピングがない場合（初回起動 or マップ破損）はスキップ
            // → syncAlarms で新しいマッピングが作られる
        }

        if didChange {
            saveIDMap()
        }
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
        // alerting 中のアラームを保護しつつキャンセル
        cancelScheduledAlarms()

        guard !Task.isCancelled else { return }

        guard await requestAuthorization() else {
            logger.warning("AlarmKit not authorized, skipping alarm sync")
            return
        }

        let enabled = entries.filter(\.isEnabled)
        var newMap: [UUID: Alarm.ID] = [:]

        for entry in enabled {
            guard !Task.isCancelled else { return }
            if let alarmID = await scheduleAlarm(for: entry) {
                newMap[entry.id] = alarmID
            }
        }

        guard !Task.isCancelled else { return }

        alarmIDMap = newMap
        scheduledAlarmCount = newMap.count
        saveIDMap()

        logger.info("Synced \(self.scheduledAlarmCount) alarms")
    }

    /// 単一アラームをスケジュール（成功時に Alarm.ID を返す）
    private func scheduleAlarm(for entry: AlarmEntry) async -> Alarm.ID? {
        let metadata = CustomAlarmMetadata(entry: entry)

        let alert = AlarmPresentation.Alert(
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
            // .countdown: AlarmKit がスヌーズを自動処理
            secondaryButtonBehavior: .countdown
        )

        let attributes = AlarmAttributes<CustomAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
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

        let config: AlarmManager.AlarmConfiguration<CustomAlarmMetadata> = .alarm(
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

    // MARK: - Cancellation

    /// スケジュール済みアラームをキャンセル（alerting 中のアラームは保護）
    private func cancelScheduledAlarms() {
        do {
            let alarms = try manager.alarms
            for alarm in alarms {
                // 鳴っている最中のアラームはキャンセルしない
                if case .alerting = alarm.state {
                    logger.info("Skipping cancel for alerting alarm: \(alarm.id)")
                    continue
                }
                do {
                    try manager.cancel(id: alarm.id)
                } catch {
                    logger.error("Failed to cancel alarm \(alarm.id): \(error.localizedDescription)")
                }
            }
        } catch {
            logger.error("Failed to fetch alarms for cancellation: \(error.localizedDescription)")
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
                    if case .alerting = alarm.state {
                        logger.info("Alarm alerting: \(alarm.id)")
                        handleAlarmFired(alarmKitID: alarm.id)
                    }
                }
            }
        }
    }

    /// 一回限りアラーム発火後に isEnabled を false にする
    private func handleAlarmFired(alarmKitID: Alarm.ID) {
        guard let entryID = alarmIDMap.first(where: { $0.value == alarmKitID })?.key else {
            return
        }

        let store = AlarmStore.shared
        guard let alarm = store.alarms.first(where: { $0.id == entryID }) else {
            return
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
