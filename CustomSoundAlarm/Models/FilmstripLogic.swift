import Foundation

/// フィルムストリップの生成状態（#88）。
///
/// 「生成中」と「生成した結果0枚」を区別する。
/// かつては `thumbnails.isEmpty` で生成中を代用していたため、映像トラックの無い
/// 音声のみファイル（動画経由で取り込んだ mp4/m4a 等）で全フレーム生成が失敗し
/// 空配列のまま正常終了したとき、スピナーが永久に回り続けていた。
enum FilmstripState: Equatable, Sendable {
    /// サムネイル生成中（スピナー表示）
    case loading
    /// 生成成功（count = 生成できた枚数）
    case ready(count: Int)
    /// 映像トラックが無い / 0枚で生成完了 → フィルムストリップは**領域ごと非表示**
    case unavailable
}

/// フィルムストリップの状態遷移（純粋関数・#88）。
enum FilmstripLogic {

    /// 映像トラックの有無から初期状態を決める。
    /// 映像が無ければ生成を始める意味がなく、即座に非表示。
    static func initialState(hasVideoTrack: Bool) -> FilmstripState {
        hasVideoTrack ? .loading : .unavailable
    }

    /// 生成の完了結果から状態を確定させる。
    ///
    /// - Parameter generatedCount: 実際に生成できたサムネイルの枚数
    /// - Returns: 1枚以上 → `.ready`、**0枚 → `.unavailable`（スピナー解除・非表示）**
    static func finishState(generatedCount: Int) -> FilmstripState {
        generatedCount > 0 ? .ready(count: generatedCount) : .unavailable
    }
}