import Testing
import Foundation
import AVFoundation
@testable import CustomSoundAlarm

/// ミュージックライブラリからの取り込み（#245）。
struct MusicLibraryImporterTests {

    // MARK: - 名前の初期値

    @Test
    func songTitleBecomesInitialName() {
        #expect(MusicLibraryImporter.initialName(title: "夜に駆ける") == "夜に駆ける")
        #expect(MusicLibraryImporter.initialName(title: "Morning Song") == "Morning Song")
    }

    @Test
    func surroundingWhitespaceIsTrimmed() {
        #expect(MusicLibraryImporter.initialName(title: "  Song Title \n") == "Song Title")
    }

    @Test
    func emptyTitleFallsBackToDefaultName() {
        let fallback = String(localized: "imported_sound_default")
        #expect(MusicLibraryImporter.initialName(title: nil) == fallback)
        #expect(MusicLibraryImporter.initialName(title: "") == fallback)
        #expect(MusicLibraryImporter.initialName(title: " \n\t ") == fallback)
    }

    // MARK: - 書き出し

    @Test
    func exportWritesPlayableM4A() async throws {
        let source = try #require(
            Bundle.main.url(forResource: "PresetMarimba", withExtension: "caf")
        )
        let exported = try #require(await MusicLibraryImporter.export(assetURL: source))
        defer { try? FileManager.default.removeItem(at: exported) }

        #expect(exported.pathExtension == "m4a")
        #expect(FileManager.default.fileExists(atPath: exported.path))

        let duration = try await AVURLAsset(url: exported).load(.duration)
        #expect(CMTimeGetSeconds(duration) > 0)
    }

    @Test
    func exportReturnsNilForMissingFile() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).m4a")
        let exported = await MusicLibraryImporter.export(assetURL: missing)
        #expect(exported == nil)
    }
}
