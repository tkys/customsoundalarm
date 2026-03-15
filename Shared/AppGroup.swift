import Foundation

/// App Group共有コンテナへのアクセス
enum AppGroup {
    static let identifier = "group.com.tkysdev.customsoundalarm"

    static var containerURL: URL {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        )!
    }

    static var userDefaults: UserDefaults {
        UserDefaults(suiteName: identifier)!
    }

    /// Share Extensionからの受け渡し用ステージングディレクトリ
    static var stagingDirectory: URL {
        let url = containerURL.appendingPathComponent("Staging", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
