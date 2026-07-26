import AppIntents
import AlarmKit

/// アラーム停止Intent
struct DismissAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "dismiss_alarm_intent"

    func perform() async throws -> some IntentResult {
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        let event = PendingAlarmEvent(
            name: AnalyticsEvent.alarmStopped(hour: hour).name,
            properties: ["hour": String(hour)],
            timestamp: now
        )
        AlarmEventBuffer.enqueue(event)

        return .result()
    }
}
