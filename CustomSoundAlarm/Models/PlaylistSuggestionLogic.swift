import Foundation

/// プレイリストの「作る1行」の条件と中身（#207）。
enum PlaylistSuggestionLogic {
    static let maxTracks = 10

    /// プレイリストが無く、取り込んだ音が2つ以上あるときだけ出す。
    static func shouldShow(playlistCount: Int, importedSoundCount: Int) -> Bool {
        playlistCount == 0 && importedSoundCount >= 2
    }

    /// 最近使った順に最大 `maxTracks` 曲。
    static func selectedSounds(
        imported: [AlarmSound],
        recentFileNames: [String],
        maxTracks: Int = maxTracks
    ) -> [AlarmSound] {
        Array(
            SoundPickerLogic.mySoundsByRecentUse(
                in: imported,
                recentFileNames: recentFileNames
            )
            .prefix(maxTracks)
        )
    }

    static func totalSeconds(_ sounds: [AlarmSound]) -> TimeInterval {
        sounds.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
    }

    /// 同じ名前が既にあるとき、空いている最小の番号を付ける。
    /// 例: なし→「マイプレイリスト」、無印あり→「マイプレイリスト 2」。
    static func availableName(base: String, existingNames: [String]) -> String {
        let existing = Set(existingNames)
        guard existing.contains(base) else { return base }
        var number = 2
        while existing.contains("\(base) \(number)") {
            number += 1
        }
        return "\(base) \(number)"
    }

    /// 提案から作るプレイリストの鳴らし方。
    static let playOrder: PlaylistPlayOrder = .oneRandom

    /// 提案から作るプレイリストの曲。
    static func makeTracks(from sounds: [AlarmSound]) -> [PlaylistTrack] {
        sounds.map { PlaylistTrack(soundFileName: $0.fileName) }
    }
}

/// 提案からプレイリストを作る（#207）。
@MainActor
enum PlaylistSuggestionService {
    /// 作ったプレイリスト。2曲未満なら作らない。
    static func create(source: PlaylistSource = .suggestion) -> Playlist? {
        let store = SoundStore.shared
        let imported = store.sounds.filter { !$0.isPreset }
        let existing = Set(store.sounds.map(\.fileName))
        let recent = SoundUsageHistory.recentFileNames(
            limit: store.sounds.count,
            existingFileNames: existing
        )
        let sounds = PlaylistSuggestionLogic.selectedSounds(
            imported: imported,
            recentFileNames: recent
        )
        guard sounds.count >= 2 else { return nil }

        let baseName = String(localized: "playlist_suggestion_name")
        let name = PlaylistSuggestionLogic.availableName(
            base: baseName,
            existingNames: PlaylistStore.shared.playlists.map(\.name)
        )
        let playlist = PlaylistStore.shared.add(
            name: name,
            tracks: PlaylistSuggestionLogic.makeTracks(from: sounds),
            playOrder: PlaylistSuggestionLogic.playOrder
        )
        AnalyticsService.shared.capture(.playlistCreated(
            trackCount: sounds.count,
            totalSecondsBucket: AnalyticsBuckets.playlistSecondsBucket(
                seconds: PlaylistSuggestionLogic.totalSeconds(sounds)
            ),
            playOrder: PlaylistSuggestionLogic.playOrder,
            transition: .off,
            source: source
        ))
        return playlist
    }
}
