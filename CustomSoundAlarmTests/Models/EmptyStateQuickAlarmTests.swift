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
            lastUsedFileName: "used.caf"
        ) == "new.caf")

        #expect(EmptyStateQuickAlarmLogic.soundFileName(
            imported: [AlarmSound(name: "Preset", fileName: "preset.caf", isPreset: true)],
            lastUsedFileName: "used.caf"
        ) == "used.caf")

        #expect(EmptyStateQuickAlarmLogic.soundFileName(
            imported: [],
            lastUsedFileName: nil
        ) == "")
    }
}
