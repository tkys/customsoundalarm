import AppIntents
import AlarmKit

/// アラーム停止Intent
///
/// 対象の AlarmKit ID をパラメータで受け取り、停止された側に応じて
/// 「今回分の取り消し」と「次回分の登録」を行う（#110）。
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
        let primary = AlarmIDMaps.loadPrimary()
        let backup = AlarmIDMaps.loadBackup()

        if let stoppedID {
            let entries = AppGroup.savedAlarmEntries
            let action = AlarmIDMaps.stopAction(
                of: stoppedID,
                primary: primary,
                backup: backup
            )
            let entryID = action.entryID
            let entry = entryID.flatMap { id in entries.first { $0.id == id } }
            let primaryID = entryID.flatMap { primary[$0] }
            let primaryState = alarms.first(where: { $0.id == primaryID })?.state

            // 一回限りの本体は「次回」が無い
            let nextDate = entry.flatMap {
                BackupAlarmLogic.nextBackupDate(
                    for: $0,
                    after: now,
                    skippingCurrentOccurrence: true
                )
            }

            let actions = StopActionPlanner.plan(
                stoppedAlarmID: stoppedID,
                primary: primary,
                backup: backup,
                primaryState: primaryState,
                hasNextBackup: nextDate != nil
            )

            var scheduledNext = false
            for stopAction in actions {
                switch stopAction {
                case .cancel(let id):
                    try? AlarmManager.shared.cancel(id: id)
                case .stop(let id):
                    // 繰り返しの本体は消さず、スヌーズのカウントダウンだけ止める
                    try? AlarmManager.shared.stop(id: id)
                case .scheduleNextBackup(let entryID):
                    guard let entry, let nextDate else { continue }
                    let newID = UUID()
                    let soundFileName = AppGroup.backupSoundNames[entryID] ?? BackupAlarmSound.fileName
                    let config = BackupAlarmFactory.configuration(
                        for: entry,
                        fireDate: nextDate,
                        alarmID: newID,
                        displayName: "",
                        soundFileName: soundFileName
                    )
                    if (try? await AlarmManager.shared.schedule(id: newID, configuration: config)) != nil {
                        var map = AlarmIDMaps.loadBackup()
                        map[entryID] = newID
                        AlarmIDMaps.saveBackup(map)
                        scheduledNext = true
                    }
                }
            }

            if !scheduledNext, let entryID {
                var map = AlarmIDMaps.loadBackup()
                map.removeValue(forKey: entryID)
                AlarmIDMaps.saveBackup(map)
            }

            if let entryID {
                var counts = AppGroup.snoozeCounts
                counts.removeValue(forKey: entryID)
                AppGroup.snoozeCounts = counts
            }

            switch action.role {
            case .primary(let entryID):
                // 直後の同期で「今回の締め切り」を復活させない
                var canceled = AppGroup.backupCanceledAt
                canceled[entryID] = now
                AppGroup.backupCanceledAt = canceled

                // 実際に今回分を取り消したときだけ計測する
                if action.counterpartAlarmID != nil {
                    AlarmEventBuffer.enqueue(PendingAlarmEvent(
                        name: AnalyticsEvent.backupAlarmCancelledByStop.name,
                        properties: [:],
                        timestamp: now
                    ))
                }
            case .backup(let entryID):
                var canceled = AppGroup.backupCanceledAt
                canceled.removeValue(forKey: entryID)
                AppGroup.backupCanceledAt = canceled
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
