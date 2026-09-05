import Foundation

/// 音源サムネイルの選択ロジック（#86・純粋関数・単体テスト対象）。
///
/// 設計方針（Issue #86 の訂正コメント）: 波形は**識別に使えない**（44pt ではどの曲も
/// 「オレンジのギザギザ」になり、現代の音源は音圧が均されてフルサイズでも塊になる）。
/// よって優先順位は:
/// 1. 動画から取り込み → **動画のフレーム**（最優先）
/// 2. アートワーク付き音声 → 埋め込み画像（ID3 / MP4 メタデータ）
/// 3. プリセット → 音源ごとの固定アイコン
/// 4. 素の音声ファイル → 波形（**最後の手段**）
enum SoundThumbnailLogic {

    /// サムネイルの表示来源
    enum Source: Equatable, Sendable {
        case videoFrame
        case artwork
        case presetIcon
        case waveform
    }

    /// 素材の種類と利用可能な候補から表示来源を決める。
    ///
    /// - Parameters:
    ///   - isPreset: プリセット音源か
    ///   - isVideo: 動画から取り込んだ音源か（映像トラックが有る）
    ///   - hasArtwork: 埋め込みアートワークが取得できたか
    static func preferredSource(isPreset: Bool, isVideo: Bool, hasArtwork: Bool) -> Source {
        if isPreset { return .presetIcon }
        if isVideo { return .videoFrame }
        if hasArtwork { return .artwork }
        return .waveform
    }

    /// プリセット音源ごとの固定アイコン（SF Symbol 名）。
    /// 未知のファイル名は汎用の音符アイコンにフォールバックする。
    static func presetIconName(fileName: String) -> String {
        switch fileName {
        case "PresetMarimba.caf": return "music.note.list"
        case "PresetBell.caf": return "bell.fill"
        case "PresetCrescendo.caf": return "speaker.wave.3.fill"
        case "PresetBeep.caf": return "speaker.wave.1.fill"
        case "PresetAscending.caf": return "chart.line.uptrend.xyaxis"
        case "PresetDualTone.caf": return "waveform"
        case "PresetMusicBox.caf": return "music.note"
        default: return "music.note"
        }
    }

    // MARK: - フレーム候補から最良の1枚を選ぶ

    /// 標本の分散を計算する（輝度の散らばり = 画面としての情報量の代理指標）。
    /// 空配列・1要素は分散 0。
    static func variance(samples: [Double]) -> Double {
        guard samples.count > 1 else { return 0 }
        let mean = samples.reduce(0, +) / Double(samples.count)
        let squaredSum = samples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return squaredSum / Double(samples.count)
    }

    /// フレーム候補の輝度分散一覧から、**最も分散が大きい**（= 暗転・無地でない）
    /// 1枚の index を選ぶ（#86: 切り出し位置の機械的選択は暗転に当たるため）。
    /// 空配列は nil。同着は先頭（最初のフレーム）を優先する。
    static func bestFrameIndex(variances: [Double]) -> Int? {
        guard !variances.isEmpty else { return nil }
        var bestIndex = 0
        var bestValue = variances[0]
        for (index, value) in variances.enumerated() where value > bestValue {
            bestIndex = index
            bestValue = value
        }
        return bestIndex
    }
}