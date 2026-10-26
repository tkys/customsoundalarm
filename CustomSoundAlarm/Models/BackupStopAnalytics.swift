import Foundation

/// 寝過ごし防止の停止を Intent から記録する（#124）。
/// アプリが閉じていても `AlarmEventBuffer` 経由で届く。
enum BackupStopAnalytics {

    static func pendingEvent(
        role: AlarmIDMaps.Role,
        entry: AlarmEntry?,
        snoozesBefore: Int?,
        hour: Int,
        timestamp: Date
    ) -> PendingAlarmEvent? {
        guard case .backup = role,
              let entry,
              let minutes = entry.backupMinutes
        else { return nil }

        let event = AnalyticsEvent.backupAlarmStopped(
            minutes: minutes,
            snoozesBefore: snoozesBefore,
            hour: hour
        )
        var ints: [String: Int] = ["minutes": minutes]
        if let snoozesBefore {
            ints["snoozes_before"] = snoozesBefore
        }
        return PendingAlarmEvent(
            name: event.name,
            properties: [:],
            intProperties: ints,
            hour: hour,
            timestamp: timestamp
        )
    }
}
