import Foundation
import Testing
@testable import CustomSoundAlarm

// MARK: - PlaylistAccess

struct PlaylistAccessTests {

    @Test
    func earlyAccess_isAvailableForEveryone() {
        #expect(PlaylistAccess.canUse(
            isPro: false,
            earlyAccessGranted: false,
            isEarlyAccessPeriod: true
        ))
    }

    @Test
    func afterLaunch_proCanUse() {
        #expect(PlaylistAccess.canUse(
            isPro: true,
            earlyAccessGranted: false,
            isEarlyAccessPeriod: false
        ))
    }

    @Test
    func afterLaunch_grantCanUse() {
        #expect(PlaylistAccess.canUse(
            isPro: false,
            earlyAccessGranted: true,
            isEarlyAccessPeriod: false
        ))
    }

    @Test
    func afterLaunch_freeWithoutGrantCannotUse() {
        #expect(!PlaylistAccess.canUse(
            isPro: false,
            earlyAccessGranted: false,
            isEarlyAccessPeriod: false
        ))
    }

    @Test
    func grant_onlyWhenUsingPlaylistFeaturesDuringEarlyAccess() {
        #expect(PlaylistAccess.shouldGrantEarlyAccess(
            usedPlaylistFeatures: true,
            isEarlyAccessPeriod: true
        ))
        #expect(!PlaylistAccess.shouldGrantEarlyAccess(
            usedPlaylistFeatures: false,
            isEarlyAccessPeriod: true
        ))
        #expect(!PlaylistAccess.shouldGrantEarlyAccess(
            usedPlaylistFeatures: true,
            isEarlyAccessPeriod: false
        ))
    }
}

// MARK: - Resync selection (#160)

struct PlaylistResyncLogicTests {

    @Test
    func selectsOnlyEnabledEntriesUsingThePlaylist() {
        let target = UUID()
        let other = UUID()
        let usingTarget = AlarmEntry(playlistID: target)
        let usingOther = AlarmEntry(playlistID: other)
        let disabledTarget = AlarmEntry(isEnabled: false, playlistID: target)
        let singleSound = AlarmEntry()

        let ids = PlaylistResyncLogic.entryIDs(
            entries: [usingTarget, usingOther, disabledTarget, singleSound],
            playlistID: target
        )

        #expect(ids == [usingTarget.id])
        #expect(!ids.contains(usingOther.id))
        #expect(!ids.contains(disabledTarget.id))
        #expect(!ids.contains(singleSound.id))
    }

    @Test
    func emptyWhenNoEntryUsesThePlaylist() {
        let ids = PlaylistResyncLogic.entryIDs(
            entries: [AlarmEntry(playlistID: UUID()), AlarmEntry()],
            playlistID: UUID()
        )
        #expect(ids.isEmpty)
    }
}
// MARK: - Render logic

struct PlaylistRenderLogicTests {

    private func tracks(_ names: [String]) -> [PlaylistTrack] {
        names.map { PlaylistTrack(soundFileName: $0) }
    }

    @Test
    func orderMode_keepsOriginalOrder() {
        let input = tracks(["a", "b", "c"])
        let result = PlaylistRenderLogic.orderedTracks(
            input,
            order: .inOrder,
            seed: 1
        )
        #expect(result == input)
    }

    @Test
    func shuffle_isDeterministicForSameSeed() {
        let input = tracks(["a", "b", "c", "d", "e"])
        let first = PlaylistRenderLogic.orderedTracks(
            input,
            order: .shuffle,
            seed: 42
        )
        let second = PlaylistRenderLogic.orderedTracks(
            input,
            order: .shuffle,
            seed: 42
        )
        #expect(first == second)
        #expect(Set(first.map(\.id)) == Set(input.map(\.id)))
    }

    @Test
    func shuffle_changesWithDifferentSeed() {
        let input = tracks(["a", "b", "c", "d", "e", "f"])
        let first = PlaylistRenderLogic.orderedTracks(
            input,
            order: .shuffle,
            seed: 1
        )
        let second = PlaylistRenderLogic.orderedTracks(
            input,
            order: .shuffle,
            seed: 2
        )
        #expect(first.map(\.soundFileName) != second.map(\.soundFileName))
    }

    @Test
    func random_returnsOneCandidate() {
        let input = tracks(["a", "b", "c"])
        for seed in 0..<20 {
            let result = PlaylistRenderLogic.orderedTracks(
                input,
                order: .oneRandom,
                seed: UInt64(seed)
            )
            #expect(result.count == 1)
            #expect(input.contains(result[0]))
        }
    }

    @Test
    func totalDuration_sumsTracksWithoutCrossfade() {
        #expect(PlaylistRenderLogic.totalDuration(
            trackDurations: [10, 20, 30],
            transition: .short
        ) == 60)
    }

    @Test
    func totalDuration_subtractsCrossfadeOverlap() {
        // 2秒のクロスフェードが2か所
        #expect(PlaylistRenderLogic.totalDuration(
            trackDurations: [10, 20, 30],
            transition: .crossfade
        ) == 56)
    }

    @Test
    func crossfadeOverlap_clampsToShortestTrack() {
        #expect(PlaylistRenderLogic.crossfadeOverlap(
            trackDurations: [1, 10, 10],
            seconds: 2
        ) == 3)
    }

    @Test
    func tenMinuteLimit_boundary() {
        #expect(PlaylistRenderLogic.isWithinLimit(
            trackDurations: [599],
            transition: .off
        ))
        #expect(PlaylistRenderLogic.isWithinLimit(
            trackDurations: [600],
            transition: .off
        ))
        #expect(!PlaylistRenderLogic.isWithinLimit(
            trackDurations: [600.1],
            transition: .off
        ))
    }

    @Test
    func tenMinuteLimit_accountsForCrossfade() {
        // 合計 601 秒でも、2秒の重なりで 599 秒になる
        #expect(PlaylistRenderLogic.isWithinLimit(
            trackDurations: [300.5, 300.5],
            transition: .crossfade
        ))
    }

    @Test
    func fadeIn_startsAtZeroAndReachesOne() {
        let sampleRate = 100.0
        #expect(PlaylistRenderLogic.fadeInGain(
            index: 0,
            fadeSeconds: 1,
            sampleRate: sampleRate
        ) == 0)
        #expect(PlaylistRenderLogic.fadeInGain(
            index: 50,
            fadeSeconds: 1,
            sampleRate: sampleRate
        ) == 0.5)
        #expect(PlaylistRenderLogic.fadeInGain(
            index: 100,
            fadeSeconds: 1,
            sampleRate: sampleRate
        ) == 1)
        #expect(PlaylistRenderLogic.fadeInGain(
            index: 101,
            fadeSeconds: 1,
            sampleRate: sampleRate
        ) == 1)
    }

    @Test
    func fadeOut_endsAtZeroAndReachesOne() {
        let sampleRate = 100.0
        #expect(PlaylistRenderLogic.fadeOutGain(
            indexFromEnd: 0,
            fadeSeconds: 1,
            sampleRate: sampleRate
        ) == 0)
        #expect(PlaylistRenderLogic.fadeOutGain(
            indexFromEnd: 50,
            fadeSeconds: 1,
            sampleRate: sampleRate
        ) == 0.5)
        #expect(PlaylistRenderLogic.fadeOutGain(
            indexFromEnd: 100,
            fadeSeconds: 1,
            sampleRate: sampleRate
        ) == 1)
    }

    @Test
    func crossfadeMix_neverExceedsInputPeak() {
        let values: [Float] = [-1, -0.5, 0, 0.25, 0.5, 1]
        for a in values {
            for b in values {
                for step in 0...10 {
                    let mix = Float(step) / 10
                    let result = PlaylistRenderLogic.crossfadeMix(a: a, b: b, mix: mix)
                    #expect(abs(result) <= max(abs(a), abs(b)) + 0.0001)
                }
            }
        }
    }

    @Test
    func fallback_skipsMissingFirstTrack() {
        let tracks = [
            PlaylistTrack(soundFileName: "Missing.caf"),
            PlaylistTrack(soundFileName: "Second.caf")
        ]
        let result = PlaylistFallbackLogic.fileName(
            tracks: tracks,
            fallbackFileName: "AlsoMissing.caf",
            isAvailable: { $0 == "Second.caf" },
            defaultFileName: "PresetMarimba.caf"
        )
        #expect(result == "Second.caf")
    }

    @Test
    func fallback_usesInputThenDefault() {
        let tracks = [PlaylistTrack(soundFileName: "Missing.caf")]
        #expect(PlaylistFallbackLogic.fileName(
            tracks: tracks,
            fallbackFileName: "PresetBell.caf",
            isAvailable: { $0 == "PresetBell.caf" },
            defaultFileName: "PresetMarimba.caf"
        ) == "PresetBell.caf")

        #expect(PlaylistFallbackLogic.fileName(
            tracks: tracks,
            fallbackFileName: "Missing2.caf",
            isAvailable: { _ in false },
            defaultFileName: "PresetMarimba.caf"
        ) == "PresetMarimba.caf")
    }

    @Test
    func playlistTotalSeconds_usesDurations() {
        let playlist = Playlist(
            name: "p",
            tracks: tracks(["a", "b", "c"])
        )
        #expect(playlist.totalSeconds(durations: ["a": 10, "b": 20]) == 30)
    }

    // MARK: - #160 data model

    @Test
    func playlistPlayOrder_mapsToSoundMode() {
        #expect(PlaylistPlayOrder.inOrder.soundMode == .playlistOrder)
        #expect(PlaylistPlayOrder.shuffle.soundMode == .playlistShuffle)
        #expect(PlaylistPlayOrder.oneRandom.soundMode == .playlistRandom)
        #expect(AlarmSoundModeLogic.soundMode(playlistID: nil, playOrder: .shuffle) == .single)
        #expect(AlarmSoundModeLogic.soundMode(playlistID: UUID(), playOrder: nil) == .playlistOrder)
    }

    @Test
    func playlistWithoutNewKeys_decodesDefaults() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "old",
          "tracks": [],
          "createdAt": 0
        }
        """
        let playlist = try JSONDecoder().decode(
            Playlist.self,
            from: Data(json.utf8)
        )
        #expect(playlist.playOrder == .inOrder)
        #expect(playlist.transition == .off)
    }

    @Test
    func playlistRoundTripKeepsPlayOrderAndTransition() throws {
        let playlist = Playlist(
            name: "p",
            playOrder: .shuffle,
            transition: .crossfade
        )
        let decoded = try JSONDecoder().decode(
            Playlist.self,
            from: JSONEncoder().encode(playlist)
        )
        #expect(decoded.playOrder == .shuffle)
        #expect(decoded.transition == .crossfade)
    }

    @Test
    func playlistDeletion_switchesToFirstExistingTrack() {
        let playlistID = UUID()
        let alarms = [
            AlarmEntry(playlistID: playlistID, fadeIn: .ten),
            AlarmEntry(playlistID: UUID())
        ]
        let updated = PlaylistDeletionLogic.updatedAlarms(
            playlistID: playlistID,
            trackFileNames: ["Missing.caf", "Second.caf"],
            alarms: alarms,
            isAvailable: { $0 == "Second.caf" },
            defaultFileName: "PresetMarimba.caf"
        )
        #expect(updated[0].playlistID == nil)
        #expect(updated[0].soundFileName == "Second.caf")
        #expect(updated[0].fadeIn == .ten)
        #expect(updated[1].playlistID != nil)
    }

    @Test
    func playlistDeletion_fallsBackToDefaultPreset() {
        let playlistID = UUID()
        let updated = PlaylistDeletionLogic.updatedAlarms(
            playlistID: playlistID,
            trackFileNames: ["Missing.caf"],
            alarms: [AlarmEntry(playlistID: playlistID)],
            isAvailable: { _ in false },
            defaultFileName: "PresetMarimba.caf"
        )
        #expect(updated[0].soundFileName == "PresetMarimba.caf")
    }
}
