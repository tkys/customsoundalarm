import AppIntents
import AlarmKit

/// アラーム停止Intent
///
/// 対象の AlarmKit ID をパラメータで受け取り、停止された側に対応する
/// もう片方（本体 ⇄ 最終アラーム）を取り消す（#110）。
/// 試しに鳴らすアラーム（#109）も同じ Intent で停止する。
struct DismissAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "dismiss_alarm_intent"

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {
        self.alarmID = ""
    }

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    func perform() async throws -> some IntentResult {
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        let stoppedID = UUID(uuidString: alarmID)

        let alarms = (try? AlarmManager.shared.alarms) ?? []
        let activeIDs = Set(alarms.map(\.id))
        let alertingIDs = Set(alarms.filter { $0.state == .alerting }.map(\.id))
        let testRecords = AppGroup.testAlarmRecords

        // 1) 試しに鳴らすアラーム
        let isTestRing = stoppedID.map { id in
            testRecords.contains { $0.id == id }
        } ?? TestRingLogic.isTestStop(
            activeIDs: activeIDs,
            alertingIDs: alertingIDs,
            records: testRecords,
            now: now
        )

        if isTestRing {
            for record in testRecords {
                try? AlarmManager.shared.cancel(id: record.id)
            }
            AppGroup.testAlarmRecords = []
            AlarmEventBuffer.enqueue(PendingAlarmEvent(
                name: AnalyticsEvent.testRingStopped(hour: hour).name,
                properties: [:],
                hour: hour,
                timestamp: now
            ))
            return .result()
        }

        // 2) 本体 / 最終アラーム
        var primary = AlarmIDMaps.loadPrimary()
        var backup = AlarmIDMaps.loadBackup()

        if let stoppedID {
            switch AlarmIDMaps.role(of: stoppedID, primary: primary, backup: backup) {
            case .primary(let entryID):
                // 本体を止めたら、同じアラームの最終アラームを取り消す
                if let backupID = backup[entryID] {
                    try? AlarmManager.shared.cancel(id: backupID)
                    backup.removeValue(forKey: entryID)
                    AlarmIDMaps.saveBackup(backup)

                    // 次の同期で同じ締め切りを復活させない（#110）
                    var canceled = AppGroup.backupCanceledAt
                    canceled[entryID] = now
                    AppGroup.backupCanceledAt = canceled
                }
            case .backup(let entryID):
                // 最終アラームを止めたら、本体のスヌーズも取り消す
                if let primaryID = primary[entryID] {
                    try? AlarmManager.shared.cancel(id: primaryID)
                }
                backup.removeValue(forKey: entryID)
                AlarmIDMaps.saveBackup(backup)
            case .unknown:
                break
            }
        }

        AlarmEventBuffer.enqueue(PendingAlarmEvent(
            name: AnalyticsEvent.alarmStopped(hour: hour).name,
            properties: [:],
            hour: hour,
            timestamp: now
        ))

        return .result()
    }
}
