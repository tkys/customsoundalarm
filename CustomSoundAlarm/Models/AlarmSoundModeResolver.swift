import Foundation

/// アラームとプレイリストから計測用の `sound_mode` を導出する（#160）。
@MainActor
enum AlarmSoundModeResolver {
    static func soundMode(for entry: AlarmEntry) -> PlaylistSoundMode {
        let playOrder = PlaylistStore.shared.playlist(id: entry.playlistID)?.playOrder
        return AlarmSoundModeLogic.soundMode(
            playlistID: entry.playlistID,
            playOrder: playOrder
        )
    }

    static func changesOrderOnStop(for entry: AlarmEntry) -> Bool {
        guard entry.playlistID != nil,
              let playlist = PlaylistStore.shared.playlist(id: entry.playlistID) else {
            return false
        }
        return playlist.playOrder.changesOrderOnStop
    }
}
