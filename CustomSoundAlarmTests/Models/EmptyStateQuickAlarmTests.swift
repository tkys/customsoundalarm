import Testing
import Foundation
@testable import CustomSoundAlarm

struct EmptyStateQuickAlarmTests {

    @Test
    func timesAreTheFourFixedMornings() {
        #expect(EmptyStateQuickAlarmLogic.times.map(\.label) == ["6:00", "6:30", "7:00", "7:30"])
    }

    @Test
    func quickAlarmIsEnabledOneTimeWithDefaults() {
        let entry = EmptyStateQuickAlarmLogic.makeEntry(
            time: QuickAlarmTime(hour: 7, minute: 0),
            soundFileName: "voice.caf",
            label: "アラーム"
        )
        #expect(entry.hour == 7)
        #expect(entry.minute == 0)
        #expect(entry.isEnabled)
        #expect(entry.repeatWeekdays.isEmpty)
        #expect(entry.soundFileName == "voice.caf")
        #expect(entry.snoozeMinutes == 9)
        #expect(entry.backupMinutes == nil)
        #expect(entry.playlistID == nil)
        #expect(entry.fadeIn == .off)
    }

    @Test
    func soundUsesLatestImportedThenLastUsed() {
        let imported = [
            AlarmSound(name: "Old", fileName: "old.caf", isPreset: false),
            AlarmSound(name: "New", fileName: "new.caf", isPreset: false),
            AlarmSound(name: "Preset", fileName: "preset.caf", isPreset: true)
        ]
        #expect(EmptyStateQuickAlarmLogic.soundFileName(
            imported: imported,
            lastUsedFileName: "used.caf",
            availableFileNames: ["old.caf", "new.caf", "preset.caf", "used.caf"]
        ) == "new.caf")

        #expect(EmptyStateQuickAlarmLogic.soundFileName(
            imported: [AlarmSound(name: "Preset", fileName: "preset.caf", isPreset: true)],
            lastUsedFileName: "used.caf",
            availableFileNames: ["preset.caf", "used.caf"]
        ) == "used.caf")

        #expect(EmptyStateQuickAlarmLogic.soundFileName(
            imported: [],
            lastUsedFileName: "deleted.caf",
            availableFileNames: ["preset.caf"]
        ) == "")

        #expect(EmptyStateQuickAlarmLogic.soundFileName(
            imported: [],
            lastUsedFileName: nil,
            availableFileNames: []
        ) == "")
    }

    @Test
    func quickAlarmUsesCarriedSnoozeAndFade() {
        let entry = EmptyStateQuickAlarmLogic.makeEntry(
            time: QuickAlarmTime(hour: 6, minute: 30),
            soundFileName: "",
            label: "Alarm",
            snoozeMinutes: 5,
            fadeIn: .fifteen
        )
        #expect(entry.snoozeMinutes == 5)
        #expect(entry.fadeIn == .fifteen)
    }

    @Test
    func quickTimeLabelFollowsLocale() {
        let time = QuickAlarmTime(hour: 6, minute: 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        #expect(time.label(locale: Locale(identifier: "ja_JP"), calendar: calendar) == "6:00")
        let english = time.label(locale: Locale(identifier: "en_US"), calendar: calendar)
        #expect(english.contains("6:00"))
        #expect(english.contains("AM"))
    }
}
