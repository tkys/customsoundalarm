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

    /// UIテスト用: DEBUG時のみ有効なfresh onboarding強制フラグ
    static var isUITestFreshOnboarding: Bool {
#if DEBUG
        return CommandLine.arguments.contains("-uitest-fresh-onboarding")
#else
        return false
#endif
    }

    /// UIテスト用: DEBUG時のみ有効なアラーム一覧シード
    static var isUITestSeedAlarms: Bool {
#if DEBUG
        return CommandLine.arguments.contains("-uitest-seed-alarms")
#else
        return false
#endif
    }

    /// オンボーディングを完了したか（#98）。
    /// 未完了かつアラーム0件・取り込み音源0件の新規インストールにだけオンボを出す。
    /// 既存ユーザーは初回起動時に条件を満たさなければ立てて以後出さない
    static var hasCompletedOnboarding: Bool {
        get { userDefaults.bool(forKey: "has_completed_onboarding") }
        set { userDefaults.set(newValue, forKey: "has_completed_onboarding") }
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

    /// 試しに鳴らしたアラームの記録（#109）。
    /// AlarmStore の外に置き、停止・60秒経過・次回起動時で確実に掃除する。
    static var testAlarmRecords: [TestAlarmRecord] {
        get {
            guard let data = userDefaults.data(forKey: "test_alarm_records"),
                  let records = try? JSONDecoder().decode([TestAlarmRecord].self, from: data)
            else { return [] }
            return records
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            userDefaults.set(data, forKey: "test_alarm_records")
        }
    }

    /// 記録中の試しアラーム ID（テスト・DismissAlarmIntent の照合用）
    static var testAlarmIDs: Set<UUID> {
        Set(testAlarmRecords.map(\.id))
    }

    /// 「アラームの音量」注記を表示済みか（#109・一度だけ）
    static var testRingVolumeNoteShown: Bool {
        get { userDefaults.bool(forKey: "test_ring_volume_note_shown") }
        set { userDefaults.set(newValue, forKey: "test_ring_volume_note_shown") }
    }

    /// 本体アラームのスヌーズ回数（entryID → 回数・#110）。
    /// 最終アラーム発火時の `snoozes_before` に使う。
    static var snoozeCounts: [UUID: Int] {
        get {
            guard let data = userDefaults.data(forKey: "snooze_counts"),
                  let map = try? JSONDecoder().decode([UUID: Int].self, from: data)
            else { return [:] }
            return map
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            userDefaults.set(data, forKey: "snooze_counts")
        }
    }

    /// 先行公開中に最終アラームを使い始めた権利（#110）。
    /// 正式に有料化した後も無料で使い続けられる。
    static var backupEarlyAccessGranted: Bool {
        get { userDefaults.bool(forKey: "backup_early_access_granted") }
        set { userDefaults.set(newValue, forKey: "backup_early_access_granted") }
    }

    /// 停止によって取り消した最終アラームの記録（entryID → 停止時刻・#110）。
    /// 次回同期で同じ締め切りを復活させないための抑制に使う。
    static var backupCanceledAt: [UUID: Date] {
        get {
            guard let data = userDefaults.data(forKey: "backup_canceled_at"),
                  let map = try? JSONDecoder().decode([UUID: Date].self, from: data)
            else { return [:] }
            return map
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            userDefaults.set(data, forKey: "backup_canceled_at")
        }
    }

    /// 保存済みアラーム（停止 Intent が最終アラームの設定を読むため・#110）
    static var savedAlarmEntries: [AlarmEntry] {
        guard let data = userDefaults.data(forKey: "saved_alarms"),
              let entries = try? JSONDecoder().decode([AlarmEntry].self, from: data)
        else { return [] }
        return entries
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

    /// 前回送信した alarm_permission の状態（#91-2: 状態が変わったときだけ送るための比較用）
    static var lastReportedPermissionStatus: String? {
        get { userDefaults.string(forKey: "last_reported_permission_status") }
        set {
            if let newValue {
                userDefaults.set(newValue, forKey: "last_reported_permission_status")
            } else {
                userDefaults.removeObject(forKey: "last_reported_permission_status")
            }
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

    /// サウンド選択画面のプリセット開閉状態（nil = 未操作・#65）
    static var presetExpandedOverride: Bool? {
        get {
            guard userDefaults.object(forKey: "preset_expanded_override") != nil else { return nil }
            return userDefaults.bool(forKey: "preset_expanded_override")
        }
        set {
            if let newValue {
                userDefaults.set(newValue, forKey: "preset_expanded_override")
            } else {
                userDefaults.removeObject(forKey: "preset_expanded_override")
            }
        }
    }

    /// Share Extensionからの受け渡し用ステージングディレクトリ
    static var stagingDirectory: URL {
        let url = containerURL.appendingPathComponent("Staging", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
