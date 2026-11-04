import Foundation

/// 「今すぐ鳴らす」で使う音の決定（編集中の未保存状態・#169）。
enum TestRingSoundPlan: Equatable, Sendable {
    /// 書き出し不要。そのまま AlarmKit に渡す。
    case direct(fileName: String)
    /// プレイリスト／フェードあり。試し鳴らし用に書き出す。
    case render(PlaylistRenderInput)
}

enum TestRingSoundLogic {
    /// 本体の試し鳴らしで使う音を決める。
    ///
    /// プレイリスト選択中は `selectedSoundFileName` が空でも `.direct("")`
    /// （= iPhone の既定音）にせず、必ず書き出し経路にする。
    static func primaryPlan(
        playlistID: UUID?,
        selectedSoundFileName: String,
        fadeIn: PlaylistFadeIn,
        entryID: UUID
    ) -> TestRingSoundPlan {
        let input = PlaylistRenderInput(
            entryID: entryID,
            playlistID: playlistID,
            fallbackFileName: selectedSoundFileName,
            fadeIn: fadeIn
        )
        if input.usesPlaylistFeatures {
            return .render(input)
        }
        return .direct(fileName: selectedSoundFileName)
    }

    /// 寝過ごし防止の試し鳴らしに使う元音を決める（本番と同じ）。
    /// プレイリストなら存在する最初の曲、無ければ選択中の1つの音。
    static func backupSourceFileName(
        playlist: Playlist?,
        fallbackFileName: String,
        isAvailable: (String) -> Bool
    ) -> String? {
        if let playlist,
           let track = playlist.tracks.first(where: {
               isAvailable($0.soundFileName)
           }) {
            return track.soundFileName
        }
        return isAvailable(fallbackFileName) ? fallbackFileName : nil
    }
}
