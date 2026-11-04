import Foundation
import Testing
@testable import CustomSoundAlarm

struct TestRingSoundLogicTests {

    @Test
    func playlistSelection_rendersInsteadOfUsingDefaultSound() {
        let playlistID = UUID()
        let entryID = UUID()

        let plan = TestRingSoundLogic.primaryPlan(
            playlistID: playlistID,
            selectedSoundFileName: "",
            fadeIn: .off,
            entryID: entryID
        )

        #expect(plan == .render(PlaylistRenderInput(
            entryID: entryID,
            playlistID: playlistID,
            fallbackFileName: "",
            fadeIn: .off
        )))
    }

    @Test
    func singleSoundWithoutFade_usesDirectFile() {
        let entryID = UUID()
        let plan = TestRingSoundLogic.primaryPlan(
            playlistID: nil,
            selectedSoundFileName: "PresetMarimba.caf",
            fadeIn: .off,
            entryID: entryID
        )
        #expect(plan == .direct(fileName: "PresetMarimba.caf"))
    }

    @Test
    func singleSoundWithFade_renders() {
        let entryID = UUID()
        let plan = TestRingSoundLogic.primaryPlan(
            playlistID: nil,
            selectedSoundFileName: "PresetMarimba.caf",
            fadeIn: .thirty,
            entryID: entryID
        )
        #expect(plan == .render(PlaylistRenderInput(
            entryID: entryID,
            fallbackFileName: "PresetMarimba.caf",
            fadeIn: .thirty
        )))
    }

    @Test
    func emptyDraftWithoutPlaylist_usesDefaultSound() {
        let plan = TestRingSoundLogic.primaryPlan(
            playlistID: nil,
            selectedSoundFileName: "",
            fadeIn: .off,
            entryID: UUID()
        )
        #expect(plan == .direct(fileName: ""))
    }

    @Test
    func backup_playlistUsesFirstAvailableTrack() {
        let playlist = Playlist(
            name: "p",
            tracks: [
                PlaylistTrack(soundFileName: "Missing.caf"),
                PlaylistTrack(soundFileName: "Second.caf")
            ]
        )
        let source = TestRingSoundLogic.backupSourceFileName(
            playlist: playlist,
            fallbackFileName: "Selected.caf",
            isAvailable: { $0 == "Second.caf" || $0 == "Selected.caf" }
        )
        #expect(source == "Second.caf")
    }

    @Test
    func backup_playlistWithoutAvailableTrackFallsBackToSelectedSound() {
        let playlist = Playlist(
            name: "p",
            tracks: [PlaylistTrack(soundFileName: "Missing.caf")]
        )
        let source = TestRingSoundLogic.backupSourceFileName(
            playlist: playlist,
            fallbackFileName: "Selected.caf",
            isAvailable: { $0 == "Selected.caf" }
        )
        #expect(source == "Selected.caf")
    }

    @Test
    func backup_singleSoundUsesSelectedSound() {
        let source = TestRingSoundLogic.backupSourceFileName(
            playlist: nil,
            fallbackFileName: "Selected.caf",
            isAvailable: { $0 == "Selected.caf" }
        )
        #expect(source == "Selected.caf")
    }

    @Test
    func backup_missingEverythingReturnsNil() {
        let source = TestRingSoundLogic.backupSourceFileName(
            playlist: nil,
            fallbackFileName: "Missing.caf",
            isAvailable: { _ in false }
        )
        #expect(source == nil)
    }
}
