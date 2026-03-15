import AppIntents
import AlarmKit

/// アラーム停止Intent
struct DismissAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "アラームを止める"

    func perform() async throws -> some IntentResult {
        .result()
    }
}

/// スヌーズIntent
struct SnoozeAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "スヌーズ"

    func perform() async throws -> some IntentResult {
        .result()
    }
}
