import Foundation

struct QuickAlarmTime: Identifiable, Equatable, Sendable {
    let hour: Int
    let minute: Int

    var id: String { String(format: "%d_%02d", hour, minute) }
    var label: String { String(format: "%d:%02d", hour, minute) }
}

/// 空の一覧から1回押して作るアラーム（#231）。
enum EmptyStateQuickAlarmLogic {
    static let times: [QuickAlarmTime] = [
        QuickAlarmTime(hour: 6, minute: 0),
        QuickAlarmTime(hour: 6, minute: 30),
        QuickAlarmTime(hour: 7, minute: 0),
        QuickAlarmTime(hour: 7, minute: 30)
    ]

    /// 最後に取り込んだ音。無ければ今の初期値（最後に使った音）。
    static func soundFileName(
        imported: [AlarmSound],
        lastUsedFileName: String?
    ) -> String {
        if let latest = imported.last(where: { !$0.isPreset }) {
            return latest.fileName
        }
        return lastUsedFileName ?? ""
    }

    static func makeEntry(
        time: QuickAlarmTime,
        soundFileName: String,
        label: String
    ) -> AlarmEntry {
        AlarmSaveLogic.newEntry(
            hour: time.hour,
            minute: time.minute,
            label: label,
            repeatWeekdays: [],
            soundFileName: soundFileName,
            snoozeMinutes: 9,
            backupMinutes: nil,
            playlistID: nil,
            fadeIn: .off,
            isEnabled: true
        )
    }
}
