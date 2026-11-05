import Foundation
import Testing
@preconcurrency import AVFoundation
@testable import CustomSoundAlarm

@Suite(.serialized)
@MainActor
struct PlaylistRenderServiceTests {

    private func makePlaylist(
        playOrder: PlaylistPlayOrder = .inOrder,
        transition: PlaylistTransition = .off
    ) -> Playlist {
        PlaylistStore.shared.add(
            name: "test-\(UUID().uuidString)",
            tracks: [PlaylistTrack(soundFileName: "PresetMarimba.caf")],
            playOrder: playOrder,
            transition: transition
        )
    }

    private func makeCAF(seconds: Double, value: Float, name: String) throws -> URL {
        let url = AudioConverter.shared.soundsDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let frames = Int(seconds * 44_100)
        let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(frames)
        )!
        buffer.frameLength = AVAudioFrameCount(frames)
        for index in 0..<frames {
            buffer.floatChannelData![0][index] = value
        }
        try file.write(from: buffer)
        return url
    }

    private func loadSamples(_ fileName: String) -> [Float] {
        let url = AudioConverter.shared.soundsDirectory.appendingPathComponent(fileName)
        guard let buffer = AudioSampleLoader.loadMono44k(fileURL: url),
              let channel = buffer.floatChannelData?[0] else {
            return []
        }
        return Array(UnsafeBufferPointer(
            start: channel,
            count: Int(buffer.frameLength)
        ))
    }

    private func peak(_ samples: [Float]) -> Float {
        samples.reduce(0) { max($0, abs($1)) }
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
    func previewSound_usesCurrentTracksTransitionAndIsDeleted() async throws {
        let nameA = "UITestPreviewA.caf"
        let nameB = "UITestPreviewB.caf"
        defer {
            for name in [nameA, nameB] {
                try? FileManager.default.removeItem(
                    at: AudioConverter.shared.soundsDirectory
                        .appendingPathComponent(name)
                )
            }
        }
        try makeCAF(seconds: 1, value: 0.1, name: nameA)
        try makeCAF(seconds: 1, value: 0.2, name: nameB)
        let tracks = [
            PlaylistTrack(soundFileName: nameA),
            PlaylistTrack(soundFileName: nameB)
        ]

        PlaylistRenderService.shared.deletePreviewSound()
        defer { PlaylistRenderService.shared.deletePreviewSound() }

        let result = await PlaylistRenderService.shared.preparePreviewSound(
            tracks: tracks,
            playOrder: .inOrder,
            transition: .crossfade
        )
        #expect(result.fileName == PlaylistRenderService.previewSoundFileName)
        #expect(!result.usedFallback)

        let samples = loadSamples(result.fileName)
        // 1秒 + 1秒 - 1秒のクロスフェード = 1秒
        #expect(abs(Double(samples.count) / 44_100 - 1.0) < 0.1)

        PlaylistRenderService.shared.deletePreviewSound()
        let url = AudioConverter.shared.soundsDirectory.appendingPathComponent(
            PlaylistRenderService.previewSoundFileName
        )
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test
    func cachedSoundFileName_returnsRenderedFileWithoutRendering() async {
        let playlist = makePlaylist()
        defer { PlaylistStore.shared.remove(id: playlist.id) }
        let entryID = UUID()
        defer { removeGeneratedFiles(entryID: entryID) }
        let input = PlaylistRenderInput(
            entryID: entryID,
            playlistID: playlist.id,
            fallbackFileName: "PresetMarimba.caf",
            fadeIn: .off
        )

        let result = await PlaylistRenderService.shared.prepareSound(for: input)
        #expect(!result.usedFallback)
        #expect(
            PlaylistRenderService.shared.cachedSoundFileName(for: input)
                == result.fileName
        )
    }

    @Test
    func testRingSound_usesFixedFileAndIsDeleted() async {
        let playlist = makePlaylist()
        defer { PlaylistStore.shared.remove(id: playlist.id) }
        let input = PlaylistRenderInput(
            entryID: UUID(),
            playlistID: playlist.id,
            fallbackFileName: "PresetMarimba.caf",
            fadeIn: .fifteen
        )
        PlaylistRenderService.shared.deleteTestRingSound()
        defer { PlaylistRenderService.shared.deleteTestRingSound() }

        let result = await PlaylistRenderService.shared.prepareTestRingSound(for: input)
        #expect(result.fileName == PlaylistRenderService.testRingSoundFileName)
        #expect(!result.usedFallback)

        let url = AudioConverter.shared.soundsDirectory.appendingPathComponent(
            PlaylistRenderService.testRingSoundFileName
        )
        #expect(FileManager.default.fileExists(atPath: url.path))

        PlaylistRenderService.shared.deleteTestRingSound()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test
    func testRingSound_repeatsShortSourceForFadeIn() async throws {
        let name = "UITestTestRingShort.caf"
        let url = AudioConverter.shared.soundsDirectory.appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try makeCAF(seconds: 5, value: 1.0, name: name)
        let playlist = PlaylistStore.shared.add(
            name: "ring-\(UUID().uuidString)",
            tracks: [PlaylistTrack(soundFileName: name)]
        )
        defer { PlaylistStore.shared.remove(id: playlist.id) }
        let input = PlaylistRenderInput(
            entryID: UUID(),
            playlistID: playlist.id,
            fadeIn: .thirty
        )
        PlaylistRenderService.shared.deleteTestRingSound()
        defer { PlaylistRenderService.shared.deleteTestRingSound() }

        let result = await PlaylistRenderService.shared.prepareTestRingSound(for: input)
        #expect(!result.usedFallback)

        let samples = loadSamples(result.fileName)
        // 5秒 + 30秒 → 7周 = 35秒。「今すぐ鳴らす」も同じ書き出し。
        #expect(abs(Double(samples.count) / 44_100 - 35) < 0.2)
        #expect(peak(samples) > 0.99)
    }

    @Test
    func renderSignatureIncludesVersion() {
        let playlist = makePlaylist()
        defer { PlaylistStore.shared.remove(id: playlist.id) }
        let input = PlaylistRenderInput(
            entryID: UUID(),
            playlistID: playlist.id,
            fadeIn: .five
        )
        let ordered = [PlaylistTrack(soundFileName: "PresetMarimba.caf")]
        let signature = PlaylistRenderService.shared.signature(
            input: input,
            ordered: ordered
        )

        #expect(
            signature.hasPrefix("v\(PlaylistRenderService.renderVersion)|"),
            "signature should start with the render version: \(signature)"
        )
        #expect(PlaylistRenderService.renderVersion >= 2)
    }

    @Test
    func cachedSoundFileName_withoutCache_returnsNil() {
        let input = PlaylistRenderInput(
            entryID: UUID(),
            playlistID: UUID(),
            fallbackFileName: "PresetMarimba.caf",
            fadeIn: .fifteen
        )
        #expect(PlaylistRenderService.shared.cachedSoundFileName(for: input) == nil)
    }

    @Test
    func singleWithoutFades_returnsOriginalFileName() async {
        let input = PlaylistRenderInput(
            entryID: UUID(),
            fallbackFileName: "PresetMarimba.caf",
            fadeIn: .off
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
            fallbackFileName: "PresetMarimba.caf",
            fadeIn: .off
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
            fallbackFileName: "PresetMarimba.caf",
            fadeIn: .five
        )

        let first = await service.prepareSound(for: base)
        #expect(first.fileName.hasSuffix(".playlist.a.caf"))

        let second = PlaylistRenderInput(
            entryID: entryID,
            playlistID: playlist.id,
            fallbackFileName: "PresetMarimba.caf",
            fadeIn: .fifteen
        )
        let secondResult = await service.prepareSound(for: second)
        #expect(secondResult.fileName.hasSuffix(".playlist.b.caf"))

        let third = PlaylistRenderInput(
            entryID: entryID,
            playlistID: playlist.id,
            fallbackFileName: "PresetMarimba.caf",
            fadeIn: .thirty
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
            fallbackFileName: "PresetMarimba.caf",
            fadeIn: .fifteen
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
            ],
            playOrder: .shuffle
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
            fallbackFileName: "PresetMarimba.caf",
            fadeIn: .off
        )
        let inputB = PlaylistRenderInput(
            entryID: entryB,
            playlistID: playlist.id,
            fallbackFileName: "PresetMarimba.caf",
            fadeIn: .off
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
            fallbackFileName: "PresetMarimba.caf",
            fadeIn: .off
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

    @Test
    func renderUsesPlaylistTransitionAndAlarmFadeIn() async throws {
        let nameA = "UITestServiceA.caf"
        let nameB = "UITestServiceB.caf"
        defer {
            for name in [nameA, nameB] {
                try? FileManager.default.removeItem(
                    at: AudioConverter.shared.soundsDirectory
                        .appendingPathComponent(name)
                )
            }
        }
        try makeCAF(seconds: 5, value: 0.1, name: nameA)
        try makeCAF(seconds: 5, value: 0.2, name: nameB)
        let playlist = PlaylistStore.shared.add(
            name: "transition-\(UUID().uuidString)",
            tracks: [
                PlaylistTrack(soundFileName: nameA),
                PlaylistTrack(soundFileName: nameB)
            ],
            transition: .crossfade
        )
        defer { PlaylistStore.shared.remove(id: playlist.id) }
        let entryID = UUID()
        defer { removeGeneratedFiles(entryID: entryID) }

        let input = PlaylistRenderInput(
            entryID: entryID,
            playlistID: playlist.id,
            fadeIn: .fifteen
        )
        let result = await PlaylistRenderService.shared.prepareSound(for: input)
        #expect(!result.usedFallback)
        let samples = loadSamples(result.fileName)
        // 1周 L = 5 + 5 - 2 = 8秒。15秒 + L = 23秒以上になる最小の周回数は4周。
        // 周の境目もクロスフェードするため、8曲 - 7回の重なり = 26秒。
        #expect(abs(Double(samples.count) / 44_100 - 26) < 0.2)
        let firstTenth = Array(samples.prefix(Int(0.1 * 44_100)))
        let lastHalf = Array(samples.suffix(Int(0.5 * 44_100)))
        #expect(peak(firstTenth) < peak(lastHalf))
    }

    @Test
    func renderUsesOneRandomPlayOrder() async throws {
        let nameA = "UITestRandomA.caf"
        let nameB = "UITestRandomB.caf"
        defer {
            for name in [nameA, nameB] {
                try? FileManager.default.removeItem(
                    at: AudioConverter.shared.soundsDirectory
                        .appendingPathComponent(name)
                )
            }
        }
        try makeCAF(seconds: 5, value: 0.1, name: nameA)
        try makeCAF(seconds: 5, value: 0.2, name: nameB)
        let playlist = PlaylistStore.shared.add(
            name: "random-\(UUID().uuidString)",
            tracks: [
                PlaylistTrack(soundFileName: nameA),
                PlaylistTrack(soundFileName: nameB)
            ],
            playOrder: .oneRandom
        )
        defer { PlaylistStore.shared.remove(id: playlist.id) }
        let entryID = UUID()
        defer { removeGeneratedFiles(entryID: entryID) }

        let input = PlaylistRenderInput(
            entryID: entryID,
            playlistID: playlist.id,
            fadeIn: .off
        )
        let result = await PlaylistRenderService.shared.prepareSound(for: input)
        #expect(!result.usedFallback)
        let samples = loadSamples(result.fileName)
        #expect(abs(Double(samples.count) / 44_100 - 5) < 0.1)
    }
}
