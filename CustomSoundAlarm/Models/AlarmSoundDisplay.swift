import Foundation

/// アラーム一覧・ベッドサイドで表示する音名（#151）。
/// プレイリストのアラームは `soundFileName` が空なので、プレイリスト名を返す。
@MainActor
enum AlarmSoundDisplay {
    static func name(for entry: AlarmEntry) -> String {
        if entry.soundMode.isPlaylist {
            return PlaylistStore.shared.playlist(id: entry.playlistID)?.name
                ?? String(localized: "playlist")
        }
        return SoundStore.shared.displayName(for: entry.soundFileName)
    }

    static func hasSound(_ entry: AlarmEntry) -> Bool {
        if entry.soundMode.isPlaylist {
            return entry.playlistID != nil
        }
        return !entry.soundFileName.isEmpty
    }

    static func isCustom(_ entry: AlarmEntry) -> Bool {
        if entry.soundMode.isPlaylist { return true }
        return !entry.soundFileName.isEmpty
    }

    /// サムネイル表示用の代表音（プレイリストは最初の曲）
    static func representativeSound(for entry: AlarmEntry) -> AlarmSound? {
        let fileName: String?
        if entry.soundMode.isPlaylist {
            fileName = PlaylistStore.shared
                .playlist(id: entry.playlistID)?
                .tracks
                .first?
                .soundFileName
        } else {
            fileName = entry.soundFileName
        }
        guard let fileName, !fileName.isEmpty else { return nil }
        return SoundStore.shared.sounds.first { $0.fileName == fileName }
    }
}
