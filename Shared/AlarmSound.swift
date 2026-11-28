import Foundation

/// アラーム音を表すモデル
/// サンドボックス内のCAFファイルへの参照を保持する
struct AlarmSound: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    /// CAF変換後のファイル名（Library/Sounds配下）
    var fileName: String
    var createdAt: Date
    /// プリセット音源かユーザーインポートか
    var isPreset: Bool
    /// 音源の長さ（秒）。追加時に計測して記録する（起動のたびに全ファイルを読まない）。
    /// Optional のため Codable 合成は decodeIfPresent になり、既存ユーザーデータ（#17 罠1）も
    /// 欠落キーで nil として安全にデコードされる。
    var durationSeconds: Double?
    /// サムネイル画像のファイル名（Library/Thumbnails配下のJPEG・#86）。
    /// 動画のフレームまたは音声の埋め込みアートワークから生成。
    /// nil = サムネイルなし（プリセットは固定アイコン、素の音声は波形で代替表示）。
    /// Optional は #17 罠1（既存データの欠落キー）対策。decodeIfPresent になり安全。
    var thumbnailFileName: String?
    /// 取り込み時（ゲイン適用前）の LUFS。診断用（#255）。
    var lufsAtImport: Double?
    /// 取り込み時に適用したゲイン dB。診断用（#255）。
    var gainDbAtImport: Double?
    /// 端末内で判定した音の種類（#202）。画面には出さない。
    var contentKind: SoundContentKind?
    /// 判定した BPM の目安（#202）。歌・歌の無い曲のときだけ。
    var bpm: Int?
    /// 歌声のラベルが最初に上位3に入った窓の開始秒（#202）。singing のときだけ。
    var vocalStartSeconds: Double?
    /// 判定の版（#202）。未判定は nil。判定規則を変えたら上げる。
    var analysisVersion: Int?

    init(
        id: UUID = UUID(),
        name: String,
        fileName: String,
        isPreset: Bool = false,
        durationSeconds: Double? = nil,
        thumbnailFileName: String? = nil,
        lufsAtImport: Double? = nil,
        gainDbAtImport: Double? = nil,
        contentKind: SoundContentKind? = nil,
        bpm: Int? = nil,
        vocalStartSeconds: Double? = nil,
        analysisVersion: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.createdAt = Date()
        self.isPreset = isPreset
        self.durationSeconds = durationSeconds
        self.thumbnailFileName = thumbnailFileName
        self.lufsAtImport = lufsAtImport
        self.gainDbAtImport = gainDbAtImport
        self.contentKind = contentKind
        self.bpm = bpm
        self.vocalStartSeconds = vocalStartSeconds
        self.analysisVersion = analysisVersion
    }
}
