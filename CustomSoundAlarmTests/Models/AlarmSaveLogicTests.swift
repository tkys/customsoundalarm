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

        #expect(updated.isEnabled, "編集して保存したらオン")
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
            playlistID: playlistID,
            fadeIn: .thirty
        )

        #expect(entry.playlistID == playlistID)
        #expect(entry.fadeIn == .thirty)
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
            playlistID: playlistID,
            fadeIn: .fifteen
        )

        #expect(updated.playlistID == playlistID)
        #expect(updated.fadeIn == .fifteen)
    }

    @Test
    func updatedEntry_keepsSkipDatesWhenOnlyTheTimeChanges() {
        let calendar = Calendar.current
        let monday = calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 16)
        )!
        let key = AlarmSkipLogic.dateKey(monday, calendar: calendar)
        var existing = AlarmEntry(
            hour: 7,
            minute: 0,
            repeatWeekdays: [2],
            skipDates: [key]
        )

        let updated = AlarmSaveLogic.updatedEntry(
            from: existing,
            hour: 8,
            minute: 30,
            label: "New",
            repeatWeekdays: [2],
            soundFileName: "",
            snoozeMinutes: 9,
            backupMinutes: nil,
            skipDates: existing.skipDates
        )

        #expect(updated.skipDates == [key])
        existing.hour = 8
        #expect(updated.hour == 8)
    }

    @Test
    func updatedEntry_dropsSkipDatesThatDoNotMatchTheNewWeekdays() {
        let calendar = Calendar.current
        let monday = calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 16)
        )!
        let tuesday = calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 17)
        )!
        let mondayKey = AlarmSkipLogic.dateKey(monday, calendar: calendar)
        let tuesdayKey = AlarmSkipLogic.dateKey(tuesday, calendar: calendar)
        let existing = AlarmEntry(
            hour: 7,
            minute: 0,
            repeatWeekdays: [2, 3],
            skipDates: [mondayKey, tuesdayKey]
        )

        let onlyMonday = AlarmSaveLogic.updatedEntry(
            from: existing,
            hour: 7,
            minute: 0,
            label: "New",
            repeatWeekdays: [2],
            soundFileName: "",
            snoozeMinutes: 9,
            backupMinutes: nil,
            skipDates: existing.skipDates
        )
        #expect(onlyMonday.skipDates == [mondayKey])

        let none = AlarmSaveLogic.updatedEntry(
            from: existing,
            hour: 7,
            minute: 0,
            label: "New",
            repeatWeekdays: [5],
            soundFileName: "",
            snoozeMinutes: 9,
            backupMinutes: nil,
            skipDates: existing.skipDates
        )
        #expect(none.skipDates.isEmpty)
    }
}
