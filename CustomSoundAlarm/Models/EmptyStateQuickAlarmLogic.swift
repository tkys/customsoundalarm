import Foundation

struct QuickAlarmTime: Identifiable, Equatable, Sendable {
    let hour: Int
    let minute: Int

    var id: String { String(format: "%d_%02d", hour, minute) }
    var label: String { label(locale: .current) }

    /// 端末の 12/24 時間設定に合わせる（#231 レビュー）。
    func label(locale: Locale, calendar: Calendar = .current) -> String {
        AlarmTimeSuggestion(hour: hour, minute: minute)
            .label(locale: locale, calendar: calendar)
    }
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
        lastUsedFileName: String?,
        availableFileNames: Set<String>
    ) -> String {
        if let latest = imported.last(where: { !$0.isPreset }) {
            return latest.fileName
        }
        if let lastUsedFileName, availableFileNames.contains(lastUsedFileName) {
            return lastUsedFileName
        }
        return ""
    }

    static func makeEntry(
        time: QuickAlarmTime,
        soundFileName: String,
        label: String,
        snoozeMinutes: Int = 9,
        fadeIn: PlaylistFadeIn = .off
    ) -> AlarmEntry {
        AlarmSaveLogic.newEntry(
            hour: time.hour,
            minute: time.minute,
            label: label,
            repeatWeekdays: [],
            soundFileName: soundFileName,
            snoozeMinutes: snoozeMinutes,
            backupMinutes: nil,
            playlistID: nil,
            fadeIn: fadeIn,
            isEnabled: true
        )
    }
}
