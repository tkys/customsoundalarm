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
            mode: .playlistOrder,
            seed: 1
        )
        #expect(result == input)
    }

    @Test
    func shuffle_isDeterministicForSameSeed() {
        let input = tracks(["a", "b", "c", "d", "e"])
        let first = PlaylistRenderLogic.orderedTracks(
            input,
            mode: .playlistShuffle,
            seed: 42
        )
        let second = PlaylistRenderLogic.orderedTracks(
            input,
            mode: .playlistShuffle,
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
            mode: .playlistShuffle,
            seed: 1
        )
        let second = PlaylistRenderLogic.orderedTracks(
            input,
            mode: .playlistShuffle,
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
                mode: .playlistRandom,
                seed: UInt64(seed)
            )
            #expect(result.count == 1)
            #expect(input.contains(result[0]))
        }
    }

    @Test
    func totalDuration_sumsTracksWithoutCrossfade() {
        let fade = PlaylistFadeSettings(gapFade: .short)
        #expect(PlaylistRenderLogic.totalDuration(
            trackDurations: [10, 20, 30],
            fade: fade
        ) == 60)
    }

    @Test
    func totalDuration_subtractsCrossfadeOverlap() {
        let fade = PlaylistFadeSettings(gapFade: .crossfade)
        // 2秒のクロスフェードが2か所
        #expect(PlaylistRenderLogic.totalDuration(
            trackDurations: [10, 20, 30],
            fade: fade
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
        let fade = PlaylistFadeSettings()
        #expect(PlaylistRenderLogic.isWithinLimit(
            trackDurations: [599],
            fade: fade
        ))
        #expect(PlaylistRenderLogic.isWithinLimit(
            trackDurations: [600],
            fade: fade
        ))
        #expect(!PlaylistRenderLogic.isWithinLimit(
            trackDurations: [600.1],
            fade: fade
        ))
    }

    @Test
    func tenMinuteLimit_accountsForCrossfade() {
        let fade = PlaylistFadeSettings(gapFade: .crossfade)
        // 合計 601 秒でも、2秒の重なりで 599 秒になる
        #expect(PlaylistRenderLogic.isWithinLimit(
            trackDurations: [300.5, 300.5],
            fade: fade
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
}
