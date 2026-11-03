import Foundation

/// プレイリストの永続化・取得（#151）。
/// App Group UserDefaults に JSON で保存する（Share Extension とは共有しない）。
@Observable
@MainActor
final class PlaylistStore {
    static let shared = PlaylistStore()

    private(set) var playlists: [Playlist] = []

    /// プレイリストの保存・削除時に呼ぶ（#160）。アラームの再登録に使う。
    var onPlaylistChanged: ((UUID) -> Void)?

    private init() {
        load()
    }

    func playlist(id: UUID?) -> Playlist? {
        guard let id else { return nil }
        return playlists.first { $0.id == id }
    }

    @discardableResult
    func add(
        name: String,
        tracks: [PlaylistTrack] = [],
        playOrder: PlaylistPlayOrder = .inOrder,
        transition: PlaylistTransition = .off
    ) -> Playlist {
        let playlist = Playlist(
            name: name,
            tracks: tracks,
            playOrder: playOrder,
            transition: transition
        )
        playlists.append(playlist)
        save()
        return playlist
    }

    func update(_ playlist: Playlist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[index] = playlist
        save()
        onPlaylistChanged?(playlist.id)
    }

    /// 新規・既存を問わず保存する（#151 の編集画面用）。
    func upsert(_ playlist: Playlist) {
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            playlists[index] = playlist
        } else {
            playlists.append(playlist)
        }
        save()
        onPlaylistChanged?(playlist.id)
    }

    func remove(id: UUID) {
        playlists.removeAll { $0.id == id }
        save()
        onPlaylistChanged?(id)
    }

    /// 削除された音をプレイリストから外し、影響したプレイリストIDを返す（#160）。
    @discardableResult
    func removeTrack(fileName: String) -> [UUID] {
        var affected: [UUID] = []
        for index in playlists.indices {
            let oldCount = playlists[index].tracks.count
            playlists[index].tracks.removeAll { $0.soundFileName == fileName }
            if playlists[index].tracks.count != oldCount {
                affected.append(playlists[index].id)
            }
        }
        guard !affected.isEmpty else { return [] }
        save()
        for id in affected {
            onPlaylistChanged?(id)
        }
        return affected
    }

    /// 曲の長さ（秒）の辞書。SoundStore の記録を使う。
    var durationsByFileName: [String: TimeInterval] {
        var durations: [String: TimeInterval] = [:]
        for sound in SoundStore.shared.sounds {
            if let duration = sound.durationSeconds {
                durations[sound.fileName] = duration
            }
        }
        return durations
    }

    func totalSeconds(for playlist: Playlist) -> TimeInterval {
        playlist.totalSeconds(durations: durationsByFileName)
    }

    func exceedsLimit(_ playlist: Playlist) -> Bool {
        totalSeconds(for: playlist) > Playlist.maxTotalSeconds + 0.5
    }

    func trackDisplayName(for fileName: String) -> String {
        SoundStore.shared.sounds.first { $0.fileName == fileName }?.name
            ?? String(localized: "sound_missing")
    }

    #if DEBUG
    func resetForUITest() {
        playlists = []
        save()
    }
    #endif

    // MARK: - Persistence

    private func load() {
        guard let data = AppGroup.playlistsData,
              let decoded = try? JSONDecoder().decode([Playlist].self, from: data) else {
            return
        }
        playlists = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(playlists) else { return }
        AppGroup.playlistsData = data
    }
}
