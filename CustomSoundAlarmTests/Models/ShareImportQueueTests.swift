import Testing
import Foundation
@testable import CustomSoundAlarm

/// 共有シートの staging キュー（#222）。
struct ShareImportQueueTests {

    @Test
    func pendingItemsAreOrderedAndClassified() throws {
        let dir = try makeStagingDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeStaged(
            in: dir,
            jsonName: "b.json",
            displayName: "Second",
            mediaName: "b.mov",
            mediaKind: "video"
        )
        try writeStaged(
            in: dir,
            jsonName: "a.json",
            displayName: "First",
            mediaName: "a.caf",
            mediaKind: "audio"
        )

        let items = ShareImportQueue.pendingItems(stagingDirectory: dir)
        #expect(items.count == 2)
        #expect(Set(items.map(\.displayName)) == ["First", "Second"])
        #expect(items.first { $0.displayName == "First" }?.mediaKind == .audio)
        #expect(items.first { $0.displayName == "Second" }?.mediaKind == .video)
    }

    @Test
    func oldMetadataInfersKindFromExtension() throws {
        let dir = try makeStagingDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let mediaURL = dir.appendingPathComponent("old.mov")
        try Data("video".utf8).write(to: mediaURL)
        let legacy = #"{"displayName":"Old","stagedFileName":"old.mov"}"#
        try Data(legacy.utf8).write(to: dir.appendingPathComponent("old.json"))

        let items = ShareImportQueue.pendingItems(stagingDirectory: dir)
        #expect(items.count == 1)
        #expect(items.first?.mediaKind == .video)
    }

    @Test
    func brokenOrMissingMediaAreSkipped() throws {
        let dir = try makeStagingDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data("not json".utf8).write(to: dir.appendingPathComponent("broken.json"))
        let pending = PendingSoundImport(
            displayName: "Missing",
            stagedFileName: "missing.caf",
            mediaKind: "audio"
        )
        try JSONEncoder().encode(pending).write(to: dir.appendingPathComponent("missing.json"))

        #expect(ShareImportQueue.pendingItems(stagingDirectory: dir).isEmpty)
    }

    @Test
    func completeRemovesMetadataAndMedia() throws {
        let dir = try makeStagingDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeStaged(
            in: dir,
            jsonName: "one.json",
            displayName: "One",
            mediaName: "one.caf",
            mediaKind: "audio"
        )
        let item = try #require(ShareImportQueue.pendingItems(stagingDirectory: dir).first)

        ShareImportQueue.complete(item)
        #expect(ShareImportQueue.pendingItems(stagingDirectory: dir).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: item.metadataURL.path))
        #expect(!FileManager.default.fileExists(atPath: item.mediaURL.path))
    }

    @Test
    func mediaKindFallsBackToAudio() {
        #expect(ShareImportQueue.mediaKind(fileExtension: "caf", stored: nil) == .audio)
        #expect(ShareImportQueue.mediaKind(fileExtension: "mp4", stored: nil) == .video)
        #expect(ShareImportQueue.mediaKind(fileExtension: "caf", stored: "video") == .video)
    }

    // MARK: - Helpers

    private func makeStagingDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareImportQueueTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeStaged(
        in dir: URL,
        jsonName: String,
        displayName: String,
        mediaName: String,
        mediaKind: String
    ) throws {
        try Data(displayName.utf8).write(to: dir.appendingPathComponent(mediaName))
        let pending = PendingSoundImport(
            displayName: displayName,
            stagedFileName: mediaName,
            mediaKind: mediaKind
        )
        try JSONEncoder().encode(pending).write(to: dir.appendingPathComponent(jsonName))
    }
}
