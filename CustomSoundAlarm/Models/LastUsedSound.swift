import Foundation

/// 「最後に使ったアラーム音」のファイル名を App Group UserDefaults に保持する。
/// 新規アラーム作成時にデフォルト選択を再現するために使用する。
/// PII は含まない（ファイル名のみ）。
enum LastUsedSound {
    private static let key = "last_used_sound_file_name"

    /// 保存時に呼ぶ。空文字列は保存しない（デフォルト音 = 未選択扱い）。
    static func save(_ fileName: String) {
        guard !fileName.isEmpty else {
            AppGroup.userDefaults.removeObject(forKey: key)
            return
        }
        AppGroup.userDefaults.set(fileName, forKey: key)
    }

    /// 最後に使った音のファイル名。未設定・空の場合は nil。
    static var fileName: String? {
        let value = AppGroup.userDefaults.string(forKey: key)
        return (value?.isEmpty == false) ? value : nil
    }

    /// クリア（テスト/リセット用）。
    static func clear() {
        AppGroup.userDefaults.removeObject(forKey: key)
    }
}
