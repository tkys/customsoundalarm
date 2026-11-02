import Foundation
import Testing
@testable import CustomSoundAlarm

@MainActor
struct PlaylistRenderServiceTests {

    private func makePlaylist() -> Playlist {
        PlaylistStore.shared.add(
            name: "test-\(UUID().uuidString)",
            tracks: [PlaylistTrack(soundFileName: "PresetMarimba.caf")]
        )
    }

    private func removeGeneratedFiles(entryID: UUID) {
        let directory = AudioConverter.shared.soundsDirectory
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        for file in files where file.lastPathComponent.hasPrefix(entryID.uuidString) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    @Test
    func singleWithoutFades_returnsOriginalFileName() async {
        let input = PlaylistRenderInput(
            entryID: UUID(),
            soundMode: .single,
            fallbackFileName: "PresetMarimba.caf"
        )
        let result = await PlaylistRenderService.shared.prepareSound(for: input)

        #expect(result.fileName == "PresetMarimba.caf")
        #expect(!result.usedFallback)
        #expect(!result.isProcessed)
    }

    @Test
    func missingPlaylist_fallsBackAndReports() async {
        let entryID = UUID()
        var reported: PlaylistRenderFailureReason?
        var fallbackCalled = false
        PlaylistRenderService.shared.onRenderFailed = { reported = $0 }
        PlaylistRenderService.shared.onFallback = { fallbackCalled = true }
        defer {
            PlaylistRenderService.shared.onRenderFailed = nil
            PlaylistRenderService.shared.onFallback = nil
        }

        let input = PlaylistRenderInput(
            entryID: entryID,
            playlistID: UUID(),
            soundMode: .playlistOrder,
            fallbackFileName: "PresetMarimba.caf"
        )
        let result = await PlaylistRenderService.shared.prepareSound(for: input)

        #expect(result.fileName == "PresetMarimba.caf")
        #expect(result.usedFallback)
        #expect(reported == .missingPlaylist)
        #expect(fallbackCalled)
        removeGeneratedFiles(entryID: entryID)
    }

    @Test
    func rendersAndAlternatesSlots() async {
        let playlist = makePlaylist()
        defer { PlaylistStore.shared.remove(id: playlist.id) }
        let entryID = UUID()
        defer { removeGeneratedFiles(entryID: entryID) }

        let service = PlaylistRenderService.shared
        let base = PlaylistRenderInput(
            entryID: entryID,
            playlistID: playlist.id,
            soundMode: .playlistOrder,
            fadeSettings: PlaylistFadeSettings(fadeIn: .ten),
            fallbackFileName: "PresetMarimba.caf"
        )

        let first = await service.prepareSound(for: base)
        #expect(first.fileName.hasSuffix(".playlist.a.caf"))

        let second = PlaylistRenderInput(
            entryID: entryID,
            playlistID: playlist.id,
            soundMode: .playlistOrder,
            fadeSettings: PlaylistFadeSettings(fadeIn: .thirty),
            fallbackFileName: "PresetMarimba.caf"
        )
        let secondResult = await service.prepareSound(for: second)
        #expect(secondResult.fileName.hasSuffix(".playlist.b.caf"))

        let third = PlaylistRenderInput(
            entryID: entryID,
            playlistID: playlist.id,
            soundMode: .playlistOrder,
            fadeSettings: PlaylistFadeSettings(fadeIn: .sixty),
            fallbackFileName: "PresetMarimba.caf"
        )
        let thirdResult = await service.prepareSound(for: third)
        #expect(thirdResult.fileName.hasSuffix(".playlist.a.caf"))

        service.cleanupUnusedFiles(inputs: [third])
        let directory = AudioConverter.shared.soundsDirectory
        let remaining = ((try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []).filter { $0.lastPathComponent.hasPrefix(entryID.uuidString) }
        #expect(remaining.count == 1)
        #expect(remaining.first?.lastPathComponent.hasSuffix(".playlist.a.caf") == true)
    }

    @Test
    func backupPlaylist_skipsFadeInAndUsesBackupName() async {
        let playlist = makePlaylist()
        defer { PlaylistStore.shared.remove(id: playlist.id) }
        let entryID = UUID()
        defer { removeGeneratedFiles(entryID: entryID) }

        let input = PlaylistRenderInput(
            entryID: entryID,
            playlistID: playlist.id,
            soundMode: .playlistOrder,
            fadeSettings: PlaylistFadeSettings(fadeIn: .thirty),
            fallbackFileName: "PresetMarimba.caf"
        )
        let result = await PlaylistRenderService.shared.prepareBackupSound(for: input)

        #expect(result != nil)
        #expect(result?.fileName.hasSuffix(".playlist.backup.a.caf") == true)
        #expect(result?.usedFallback == false)
    }
}
