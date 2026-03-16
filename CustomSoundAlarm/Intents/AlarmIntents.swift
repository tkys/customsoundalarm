import AppIntents
import AlarmKit

/// アラーム停止Intent
struct DismissAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "dismiss_alarm_intent"

    func perform() async throws -> some IntentResult {
        .result()
    }
}
