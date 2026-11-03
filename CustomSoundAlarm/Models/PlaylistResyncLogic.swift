import Foundation

/// プレイリスト編集・音削除後に再登録するアラームを選ぶ純ロジック（#160）。
enum PlaylistResyncLogic {
    static func entryIDs(
        entries: [AlarmEntry],
        playlistID: UUID
    ) -> Set<UUID> {
        Set(
            entries
                .filter { $0.isEnabled && $0.playlistID == playlistID }
                .map(\.id)
        )
    }
}
