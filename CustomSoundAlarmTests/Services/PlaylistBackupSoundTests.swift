import Foundation
import Testing
@testable import CustomSoundAlarm

/// プレイリストの寝過ごし防止は、存在する最初の曲の「大きくした版」で鳴らす（#151）。
@MainActor
struct PlaylistBackupSoundTests {

    private var directory: URL {
        AudioConverter.shared.soundsDirectory
    }

    private func touch(_ name: String) throws {
        try Data("x".utf8).write(to: directory.appendingPathComponent(name))
    }

    private func removeIfExists(_ names: [String]) {
        for name in names {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    @Test
    func backupSource_skipsMissingFirstTrack() throws {
        let sourceName = "UITestPlaylistBackup.caf"
        removeIfExists([sourceName])
        defer { removeIfExists([sourceName]) }
        try touch(sourceName)

        let playlist = PlaylistStore.shared.add(
            name: "backup-\(UUID().uuidString)",
            tracks: [
                PlaylistTrack(soundFileName: "Missing.caf"),
                PlaylistTrack(soundFileName: sourceName)
            ]
        )
        defer { PlaylistStore.shared.remove(id: playlist.id) }

        let entry = AlarmEntry(playlistID: playlist.id)
        #expect(AlarmScheduler.shared.backupSourceFileName(for: entry) == sourceName)
    }

    @Test
    func backupSound_usesLoudVariantWhenAvailable() throws {
        let source = "UITestPlaylistLoud.caf"
        let variant = "UITestPlaylistLoud.loud.caf"
        let metadata = "UITestPlaylistLoud.loud.json"
        removeIfExists([source, variant, metadata])
        defer { removeIfExists([source, variant, metadata]) }
        try touch(source)
        try touch(variant)
        let data = try JSONEncoder().encode(
            LoudVariantMetadata(version: LoudVariantGenerator.version)
        )
        try data.write(to: directory.appendingPathComponent(metadata))

        #expect(BackupLoudVariantService.resolvedSoundFileName(
            forSourceFileName: source
        ) == variant)
    }

    @Test
    func backupSound_fallsBackToPresetWhenNoVariant() throws {
        let source = "UITestPlaylistNoVariant.caf"
        removeIfExists([source])
        defer { removeIfExists([source]) }
        try touch(source)

        #expect(BackupLoudVariantService.resolvedSoundFileName(
            forSourceFileName: source
        ) == BackupAlarmSound.fileName)
    }
}
