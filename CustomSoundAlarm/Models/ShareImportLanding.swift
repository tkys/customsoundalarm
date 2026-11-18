import Foundation

enum ShareImportDestination: String, Sendable, CaseIterable {
    case addAlarm = "add_alarm"
    case library
}

/// 共有から保存したあとの着地先を、タブをまたいで伝える（#246）。
@Observable
@MainActor
final class ShareImportLanding {
    static let shared = ShareImportLanding()

    /// ライブラリでスクロール＆ハイライトする音のファイル名。
    var librarySoundFileName: String?

    private init() {}
}
