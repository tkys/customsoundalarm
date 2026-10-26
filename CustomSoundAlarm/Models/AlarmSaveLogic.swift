import Foundation

/// 追加・編集画面の保存ロジック（#122）。
/// 保存したアラームは必ずオンにする（時計アプリと同じく、保存＝鳴らしたい）。
enum AlarmSaveLogic {

    static func newEntry(
        hour: Int,
        minute: Int,
        label: String,
        repeatWeekdays: [Int],
        soundFileName: String,
        snoozeMinutes: Int,
        backupMinutes: Int?
    ) -> AlarmEntry {
        AlarmEntry(
            hour: hour,
            minute: minute,
            isEnabled: true,
            label: label,
            repeatWeekdays: repeatWeekdays,
            soundFileName: soundFileName,
            snoozeMinutes: snoozeMinutes,
            backupMinutes: backupMinutes
        )
    }

    static func updatedEntry(
        from existing: AlarmEntry,
        hour: Int,
        minute: Int,
        label: String,
        repeatWeekdays: [Int],
        soundFileName: String,
        snoozeMinutes: Int,
        backupMinutes: Int?
    ) -> AlarmEntry {
        var updated = existing
        updated.hour = hour
        updated.minute = minute
        updated.label = label
        updated.repeatWeekdays = repeatWeekdays
        updated.soundFileName = soundFileName
        updated.snoozeMinutes = snoozeMinutes
        updated.backupMinutes = backupMinutes
        // 編集画面にオン/オフは置かない。保存したら必ずオン（#122）
        updated.isEnabled = true
        return updated
    }
}
