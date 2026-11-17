import Foundation

/// Share Extensionからメインアプリへの受け渡し用データ
struct PendingSoundImport: Codable {
    let displayName: String
    let stagedFileName: String
    /// 共有された種類（audio / video）。1.8.2 以前のデータでは nil。
    var mediaKind: String? = nil
}
