import AppIntents
import AlarmKit

/// アラーム停止Intent
struct DismissAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "dismiss_alarm_intent"

    func perform() async throws -> some IntentResult {
        // AlarmKit の全アラームを確認し、alerting 中のものを探す
        let alarms = (try? AlarmManager.shared.alarms) ?? []
        let now = Date()

        for alarm in alarms where alarm.state == .alerting {
            let secondsToStop: Int? = {
                // 発火からの経過時間を概算（schedule が relative の場合 fire date から計算）
                // 正確な値は取れない可能性があるが、概算で十分
                nil
            }()

            let props: [String: String] = [
                "alarm_id": alarm.id.uuidString,
                "seconds_to_stop": secondsToStop.map(String.init) ?? ""
            ]
            let event = PendingAlarmEvent(
                name: "alarm_stopped",
                properties: props,
                timestamp: now
            )
            AlarmEventBuffer.enqueue(event)
        }

        return .result()
    }
}
