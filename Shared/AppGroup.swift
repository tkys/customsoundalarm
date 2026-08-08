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

    /// ユーザーが削除したプリセットの fileName（再登録防止用・#45 罠1）
    static var dismissedPresetFileNames: Set<String> {
        get {
            guard let data = userDefaults.data(forKey: "dismissed_preset_file_names"),
                  let ids = try? JSONDecoder().decode(Set<String>.self, from: data)
            else { return [] }
            return ids
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            userDefaults.set(data, forKey: "dismissed_preset_file_names")
        }
    }

    /// ベッドサイド時計の配色テーマ（raw文字列・#56）
    static var bedsideColorThemeRaw: String {
        get { userDefaults.string(forKey: "bedside_color_theme") ?? "white" }
        set { userDefaults.set(newValue, forKey: "bedside_color_theme") }
    }

    /// ベッドサイド時計のユーザー設定（JSON・#59）
    static var bedsideSettingsData: Data? {
        get { userDefaults.data(forKey: "bedside_settings") }
        set {
            if let newValue {
                userDefaults.set(newValue, forKey: "bedside_settings")
            } else {
                userDefaults.removeObject(forKey: "bedside_settings")
            }
        }
    }

    /// ベッドサイドモードの初回ヒント表示済みフラグ（#62）
    static var bedsideHintShown: Bool {
        get { userDefaults.bool(forKey: "bedside_hint_shown") }
        set { userDefaults.set(newValue, forKey: "bedside_hint_shown") }
    }

    /// Share Extensionからの受け渡し用ステージングディレクトリ
    static var stagingDirectory: URL {
        let url = containerURL.appendingPathComponent("Staging", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
