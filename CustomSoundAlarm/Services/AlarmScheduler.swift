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

    private init() {}

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

    // MARK: - Scheduling

    /// 全アラームを同期
    func syncAlarms(_ entries: [AlarmEntry]) async {
        await cancelAllAlarms()

        guard await requestAuthorization() else {
            logger.warning("AlarmKit not authorized, skipping alarm sync")
            return
        }

        let enabled = entries.filter(\.isEnabled)
        for entry in enabled {
            await scheduleAlarm(for: entry)
        }

        logger.info("Synced \(self.scheduledAlarmCount) alarms")
    }

    /// 単一アラームをスケジュール
    func scheduleAlarm(for entry: AlarmEntry) async {
        guard await requestAuthorization() else { return }

        let metadata = CustomAlarmMetadata(entry: entry)

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: entry.label),
            stopButton: AlarmButton(
                text: "止める",
                textColor: .red,
                systemImageName: "stop.fill"
            ),
            secondaryButton: AlarmButton(
                text: "スヌーズ",
                textColor: .blue,
                systemImageName: "clock.fill"
            ),
            secondaryButtonBehavior: .custom
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
            // 一回限り
            schedule = .relative(.init(time: alarmTime))
        } else if entry.repeatWeekdays.count == 7 {
            // 毎日
            schedule = .relative(.init(time: alarmTime))
        } else {
            // 曜日指定
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
            secondaryIntent: SnoozeAlarmIntent(),
            sound: entry.soundFileName.isEmpty ? .default : .named(entry.soundFileName)
        )

        do {
            let alarmID = Alarm.ID()
            _ = try await manager.schedule(id: alarmID, configuration: config)
            scheduledAlarmCount += 1
            logger.info("Scheduled alarm: \(entry.timeString) - \(entry.label) - sound: \(entry.soundFileName.isEmpty ? "default" : entry.soundFileName)")
        } catch {
            logger.error("Failed to schedule alarm: \(error.localizedDescription)")
        }
    }

    /// 全アラームをキャンセル
    func cancelAllAlarms() async {
        for await alarms in manager.alarmUpdates {
            for alarm in alarms {
                try? manager.cancel(id: alarm.id)
            }
            break
        }
        scheduledAlarmCount = 0
        logger.info("Cancelled all alarms")
    }

    /// アラーム状態の監視
    func observeAlarms(onAlert: @escaping (String) -> Void) {
        Task {
            for await alarms in manager.alarmUpdates {
                for alarm in alarms {
                    if case .alerting = alarm.state {
                        logger.info("Alarm alerting: \(alarm.id)")
                        onAlert(alarm.id.uuidString)
                    }
                }
            }
        }
    }
}
