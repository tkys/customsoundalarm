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

    init(id: UUID = UUID(), name: String, fileName: String, isPreset: Bool = false) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.createdAt = Date()
        self.isPreset = isPreset
    }
}
