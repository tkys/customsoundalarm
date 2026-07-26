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

    /// 初回インストールバージョン（起動時に1度だけ記録）
    static var firstInstallVersion: String? {
        get { userDefaults.string(forKey: "first_install_version") }
        set { userDefaults.set(newValue, forKey: "first_install_version") }
    }

    /// スヌーズ記録済みの AlarmEntry.ID（App Group 永続化。スヌーズ検知の二重計上防止）
    static var snoozedAlarmEntryIDs: Set<UUID> {
        get {
            guard let data = userDefaults.data(forKey: "snoozed_alarm_entry_ids"),
                  let ids = try? JSONDecoder().decode(Set<UUID>.self, from: data)
            else { return [] }
            return ids
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            userDefaults.set(data, forKey: "snoozed_alarm_entry_ids")
        }
    }

    /// Share Extensionからの受け渡し用ステージングディレクトリ
    static var stagingDirectory: URL {
        let url = containerURL.appendingPathComponent("Staging", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
