import Foundation

/// Share Extensionからメインアプリへの受け渡し用データ
struct PendingSoundImport: Codable {
    let displayName: String
    let stagedFileName: String
}
