import Testing
import Foundation
@testable import CustomSoundAlarm

struct AlarmSaveLogicTests {

    @Test
    func newEntry_isAlwaysEnabled() {
        let entry = AlarmSaveLogic.newEntry(
            hour: 7,
            minute: 30,
            label: "Morning",
            repeatWeekdays: [2, 3],
            soundFileName: "a.caf",
            snoozeMinutes: 5,
            backupMinutes: 15
        )

        #expect(entry.isEnabled)
        #expect(entry.hour == 7)
        #expect(entry.minute == 30)
        #expect(entry.label == "Morning")
        #expect(entry.repeatWeekdays == [2, 3])
        #expect(entry.soundFileName == "a.caf")
        #expect(entry.snoozeMinutes == 5)
        #expect(entry.backupMinutes == 15)
    }

    @Test
    func updatedEntry_forcesEnabled() {
        let existing = AlarmEntry(
            hour: 6,
            minute: 0,
            isEnabled: false,
            label: "Old",
            repeatWeekdays: [1],
            soundFileName: "old.caf",
            snoozeMinutes: 9,
            backupMinutes: nil
        )

        let updated = AlarmSaveLogic.updatedEntry(
            from: existing,
            hour: 8,
            minute: 15,
            label: "New",
            repeatWeekdays: [2, 4],
            soundFileName: "new.caf",
            snoozeMinutes: 10,
            backupMinutes: 20
        )

        #expect(updated.isEnabled, "編集して保存したら必ずオン")
        #expect(updated.id == existing.id)
        #expect(updated.hour == 8)
        #expect(updated.minute == 15)
        #expect(updated.label == "New")
        #expect(updated.repeatWeekdays == [2, 4])
        #expect(updated.soundFileName == "new.caf")
        #expect(updated.snoozeMinutes == 10)
        #expect(updated.backupMinutes == 20)
    }

    @Test
    func newEntry_carriesPlaylistFields() {
        let playlistID = UUID()
        let entry = AlarmSaveLogic.newEntry(
            hour: 7,
            minute: 0,
            label: "Playlist",
            repeatWeekdays: [],
            soundFileName: "",
            snoozeMinutes: 9,
            backupMinutes: nil,
            soundMode: .playlistShuffle,
            playlistID: playlistID,
            fadeSettings: PlaylistFadeSettings(fadeIn: .thirty)
        )

        #expect(entry.soundMode == .playlistShuffle)
        #expect(entry.playlistID == playlistID)
        #expect(entry.fadeSettings.fadeIn == .thirty)
        #expect(entry.usesPlaylistFeatures)
    }

    @Test
    func updatedEntry_carriesPlaylistFields() {
        let existing = AlarmEntry()
        let playlistID = UUID()
        let updated = AlarmSaveLogic.updatedEntry(
            from: existing,
            hour: 8,
            minute: 15,
            label: "New",
            repeatWeekdays: [],
            soundFileName: "",
            snoozeMinutes: 9,
            backupMinutes: nil,
            soundMode: .playlistOrder,
            playlistID: playlistID,
            fadeSettings: PlaylistFadeSettings(gapFade: .crossfade)
        )

        #expect(updated.soundMode == .playlistOrder)
        #expect(updated.playlistID == playlistID)
        #expect(updated.fadeSettings.gapFade == .crossfade)
    }
}
