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

    init(id: UUID = UUID(), name: String, fileName: String, isPreset: Bool = false, durationSeconds: Double? = nil, thumbnailFileName: String? = nil) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.createdAt = Date()
        self.isPreset = isPreset
        self.durationSeconds = durationSeconds
        self.thumbnailFileName = thumbnailFileName
    }
}
