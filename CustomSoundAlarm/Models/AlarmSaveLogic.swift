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
        backupMinutes: Int?,
        playlistID: UUID? = nil,
        fadeIn: PlaylistFadeIn = .off,
        isEnabled: Bool = true,
        skipsHolidays: Bool = false,
        holidayRingOverrides: [String] = [],
        skipDates: [String] = []
    ) -> AlarmEntry {
        AlarmEntry(
            hour: hour,
            minute: minute,
            isEnabled: isEnabled,
            label: label,
            repeatWeekdays: repeatWeekdays,
            soundFileName: soundFileName,
            snoozeMinutes: snoozeMinutes,
            backupMinutes: backupMinutes,
            playlistID: playlistID,
            fadeIn: fadeIn,
            skipDates: skipDates,
            skipsHolidays: skipsHolidays,
            holidayRingOverrides: holidayRingOverrides
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
        backupMinutes: Int?,
        playlistID: UUID? = nil,
        fadeIn: PlaylistFadeIn = .off,
        skipsHolidays: Bool? = nil,
        holidayRingOverrides: [String]? = nil,
        skipDates: [String]? = nil
    ) -> AlarmEntry {
        var updated = existing
        updated.hour = hour
        updated.minute = minute
        updated.label = label
        updated.repeatWeekdays = repeatWeekdays
        updated.soundFileName = soundFileName
        updated.snoozeMinutes = snoozeMinutes
        updated.backupMinutes = backupMinutes
        updated.playlistID = playlistID
        updated.fadeIn = fadeIn
        if let skipsHolidays { updated.skipsHolidays = skipsHolidays }
        if let holidayRingOverrides { updated.holidayRingOverrides = holidayRingOverrides }
        if let skipDates {
            // 時刻を変えても休む日は残す。曜日を変えたら合わない日付は黙って落とす（#197）
            if repeatWeekdays.isEmpty {
                updated.skipDates = []
            } else {
                let calendar = Calendar.current
                updated.skipDates = skipDates.filter { key in
                    guard let date = AlarmSkipLogic.date(fromKey: key, calendar: calendar) else {
                        return false
                    }
                    return repeatWeekdays.contains(calendar.component(.weekday, from: date))
                }.sorted()
            }
        }
        // 編集画面にオン/オフは置かない。保存したらオン（#122）
        updated.isEnabled = true
        return updated
    }
}
