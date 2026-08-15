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

    init(id: UUID = UUID(), name: String, fileName: String, isPreset: Bool = false, durationSeconds: Double? = nil) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.createdAt = Date()
        self.isPreset = isPreset
        self.durationSeconds = durationSeconds
    }
}
