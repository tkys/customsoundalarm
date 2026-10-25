import Foundation
import AlarmKit

/// 最終アラームの AlarmKit 設定を組み立てる（#110）。
/// 通常同期と停止 Intent の両方から使う。
enum BackupAlarmFactory {

    static func configuration(
        for entry: AlarmEntry,
        fireDate: Date,
        alarmID: UUID,
        displayName: String
    ) -> AlarmManager.AlarmConfiguration<CustomAlarmMetadata> {
        let title = LocalizedStringResource("backup_alarm_title")
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: title)
        } else {
            alert = AlarmPresentation.Alert(
                title: title,
                stopButton: AlarmButton(
                    text: "stop_alarm",
                    textColor: .red,
                    systemImageName: "stop.fill"
                )
            )
        }

        let attributes = AlarmAttributes<CustomAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert, countdown: nil, paused: nil),
            metadata: CustomAlarmMetadata(entry: entry, soundDisplayName: displayName),
            tintColor: .red
        )

        return AlarmManager.AlarmConfiguration(
            countdownDuration: nil,
            schedule: .fixed(fireDate),
            attributes: attributes,
            stopIntent: DismissAlarmIntent(alarmID: alarmID.uuidString),
            sound: .named(BackupAlarmLogic.soundFileName)
        )
    }
}
