import AppIntents
import AlarmKit

/// アラーム停止Intent
///
/// 試しに鳴らすアラーム（#109）も同じ Intent で停止する。停止時に
/// `AppGroup.testAlarmRecords` と照合し、試しの停止なら `test_ring_stopped` を送る。
struct DismissAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "dismiss_alarm_intent"

    func perform() async throws -> some IntentResult {
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)

        let alarms = (try? AlarmManager.shared.alarms) ?? []
        let activeIDs = Set(alarms.map(\.id))
        let alertingIDs = Set(alarms.filter { $0.state == .alerting }.map(\.id))
        let records = AppGroup.testAlarmRecords

        let event: PendingAlarmEvent
        if TestRingLogic.isTestStop(
            activeIDs: activeIDs,
            alertingIDs: alertingIDs,
            records: records,
            now: now
        ) {
            // 停止した試しアラームを後始末する（鳴り終わりではなくボタン停止なので cancel で消す）
            for record in records {
                try? AlarmManager.shared.cancel(id: record.id)
            }
            AppGroup.testAlarmRecords = []
            event = PendingAlarmEvent(
                name: AnalyticsEvent.testRingStopped(hour: hour).name,
                properties: [:],
                hour: hour,
                timestamp: now
            )
        } else {
            event = PendingAlarmEvent(
                name: AnalyticsEvent.alarmStopped(hour: hour).name,
                properties: [:],
                hour: hour,
                timestamp: now
            )
        }

        AlarmEventBuffer.enqueue(event)

        return .result()
    }
}
