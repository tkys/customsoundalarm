import Testing
import Foundation
@testable import CustomSoundAlarm

/// プレイリストの「作る1行」の条件と中身（#207）。
struct PlaylistSuggestionLogicTests {

    private func sound(_ name: String) -> AlarmSound {
        AlarmSound(name: name, fileName: "\(name).caf", durationSeconds: 10)
    }

    @Test
    func shownOnlyWithoutPlaylistsAndWithTwoImportedSounds() {
        #expect(PlaylistSuggestionLogic.shouldShow(playlistCount: 0, importedSoundCount: 2))
        #expect(PlaylistSuggestionLogic.shouldShow(playlistCount: 0, importedSoundCount: 10))
        #expect(!PlaylistSuggestionLogic.shouldShow(playlistCount: 0, importedSoundCount: 1))
        #expect(!PlaylistSuggestionLogic.shouldShow(playlistCount: 1, importedSoundCount: 5))
    }

    @Test
    func selectedSoundsUseRecentOrderAndStopAtTen() {
        let imported = (1...12).map { sound("sound\($0)") }
        let recent = (1...12).reversed().map { "sound\($0).caf" }

        let selected = PlaylistSuggestionLogic.selectedSounds(
            imported: imported,
            recentFileNames: recent
        )
        #expect(selected.count == 10)
        #expect(selected.map(\.fileName).first == "sound12.caf")
        #expect(selected.map(\.fileName).last == "sound3.caf")
    }

    @Test
    func selectedSoundsKeepRecentFirstThenOriginalOrder() {
        let imported = [sound("a"), sound("b"), sound("c")]
        let selected = PlaylistSuggestionLogic.selectedSounds(
            imported: imported,
            recentFileNames: ["c.caf"]
        )
        #expect(selected.map(\.fileName) == ["c.caf", "a.caf", "b.caf"])
    }

    @Test
    func createdPlaylistUsesTheSelectedSoundsAndOneRandom() {
        let sounds = [sound("a"), sound("b"), sound("c")]
        let tracks = PlaylistSuggestionLogic.makeTracks(from: sounds)
        #expect(tracks.map(\.soundFileName) == ["a.caf", "b.caf", "c.caf"])
        #expect(PlaylistSuggestionLogic.playOrder == .oneRandom)
        #expect(PlaylistSuggestionLogic.totalSeconds(sounds) == 30)
    }

    @Test
    func totalSecondsIgnoresUnknownDurations() {
        let sounds = [
            AlarmSound(name: "a", fileName: "a.caf", durationSeconds: 12),
            AlarmSound(name: "b", fileName: "b.caf"),
        ]
        #expect(PlaylistSuggestionLogic.totalSeconds(sounds) == 12)
    }
}
