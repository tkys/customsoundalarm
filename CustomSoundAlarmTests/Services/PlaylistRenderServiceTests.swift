import Foundation
import Testing
@testable import CustomSoundAlarm

@Suite(.serialized)
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
    func cleanupKeepsRegisteredFileAndOnlyRemovesOldTemps() async throws {
        let playlist = makePlaylist()
        defer { PlaylistStore.shared.remove(id: playlist.id) }
        let entryID = UUID()
        defer { removeGeneratedFiles(entryID: entryID) }
        let input = PlaylistRenderInput(
            entryID: entryID,
            playlistID: playlist.id,
            soundMode: .playlistOrder,
            fadeSettings: PlaylistFadeSettings(fadeIn: .ten),
            fallbackFileName: "PresetMarimba.caf"
        )
        let rendered = await PlaylistRenderService.shared.prepareSound(for: input)
        #expect(!rendered.usedFallback)

        let directory = AudioConverter.shared.soundsDirectory
        let registeredName = "\(entryID.uuidString).playlist.registered.caf"
        let oldSlotName = "\(entryID.uuidString).playlist.b.caf"
        let orphanID = UUID()
        let orphanName = "\(orphanID.uuidString).playlist.a.caf"
        let freshTempName = "\(entryID.uuidString).playlist.a.fresh.tmp.caf"
        let oldTempName = "\(entryID.uuidString).playlist.b.old.tmp.caf"

        for name in [registeredName, oldSlotName, orphanName, freshTempName, oldTempName] {
            FileManager.default.createFile(
                atPath: directory.appendingPathComponent(name).path,
                contents: Data()
            )
        }
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-11 * 60)],
            ofItemAtPath: directory.appendingPathComponent(oldTempName).path
        )

        PlaylistRenderService.shared.cleanupUnusedFiles(
            inputs: [input],
            keeping: [registeredName]
        )

        func exists(_ name: String) -> Bool {
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(name).path
            )
        }
        #expect(exists(rendered.fileName))
        #expect(exists(registeredName))
        #expect(!exists(oldSlotName))
        #expect(!exists(orphanName))
        #expect(exists(freshTempName))
        #expect(!exists(oldTempName))
    }

    @Test
    func forceNewOrder_onlyAffectsTheStoppedAlarm() async {
        let playlist = PlaylistStore.shared.add(
            name: "shuffle-\(UUID().uuidString)",
            tracks: [
                PlaylistTrack(soundFileName: "PresetMarimba.caf"),
                PlaylistTrack(soundFileName: "PresetBell.caf")
            ]
        )
        defer { PlaylistStore.shared.remove(id: playlist.id) }
        let entryA = UUID()
        let entryB = UUID()
        defer {
            removeGeneratedFiles(entryID: entryA)
            removeGeneratedFiles(entryID: entryB)
        }
        let inputA = PlaylistRenderInput(
            entryID: entryA,
            playlistID: playlist.id,
            soundMode: .playlistShuffle,
            fallbackFileName: "PresetMarimba.caf"
        )
        let inputB = PlaylistRenderInput(
            entryID: entryB,
            playlistID: playlist.id,
            soundMode: .playlistShuffle,
            fallbackFileName: "PresetMarimba.caf"
        )

        _ = await PlaylistRenderService.shared.prepareSound(for: inputA)
        let firstB = await PlaylistRenderService.shared.prepareSound(for: inputB)
        _ = await PlaylistRenderService.shared.prepareSound(
            for: inputA,
            forceNewOrder: true
        )
        let secondB = await PlaylistRenderService.shared.prepareSound(for: inputB)

        #expect(secondB.fileName == firstB.fileName)
    }

    @Test
    func cleanup_removesOldPlaylistBackupFilesUnlessRegistered() {
        let entryID = UUID()
        let input = PlaylistRenderInput(
            entryID: entryID,
            soundMode: .playlistOrder,
            fallbackFileName: "PresetMarimba.caf"
        )
        let directory = AudioConverter.shared.soundsDirectory
        let oldBackup = "\(entryID.uuidString).playlist.backup.a.caf"
        let registeredBackup = "\(entryID.uuidString).playlist.backup.b.caf"
        defer {
            for name in [oldBackup, registeredBackup] {
                try? FileManager.default.removeItem(
                    at: directory.appendingPathComponent(name)
                )
            }
        }
        for name in [oldBackup, registeredBackup] {
            FileManager.default.createFile(
                atPath: directory.appendingPathComponent(name).path,
                contents: Data()
            )
        }

        PlaylistRenderService.shared.cleanupUnusedFiles(
            inputs: [input],
            keeping: [registeredBackup]
        )

        #expect(!FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(oldBackup).path
        ))
        #expect(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(registeredBackup).path
        ))
    }
}
