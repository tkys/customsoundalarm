import Foundation

/// サウンドの「使用履歴」を App Group UserDefaults に `[fileName: 最終使用日時]` で保持する。
/// `AlarmSound`（Codable 永続モデル）には新フィールドを足さず、**別の履歴マップ**で持つ
/// （マイグレーション回避・低リスク）。
///
/// - #6 の「前回使った音（単一値）」を本履歴で包含・置換。初回アクセスで一回限りマイグレーションする。
/// - PII は含まない（ファイル名とUNIX時刻のみ）。
/// - 履歴は新しい順に最大 `maxEntries` 件に切り詰め（無制限増加を防止）。
enum SoundUsageHistory {
    /// 履歴マップの UserDefaults キー（値: `[fileName: TimeInterval]`）。
    private static let mapKey = "sound_usage_history"
    /// #6 で使っていた単一値のキー（マイグレーション元）。
    private static let legacySingleKey = "last_used_sound_file_name"
    /// 履歴の最大保持件数。
    private static let maxEntries = 20

    // MARK: - Public API

    /// 指定音の使用を記録する。
    /// - Parameters:
    ///   - fileName: サウンドファイル名。空文字列は無視（デフォルト音 = 未選択扱い）。
    ///   - date: 使用日時（テスト注入用）。省略時は現在時刻。
    static func recordUsage(_ fileName: String, at date: Date = Date()) {
        guard !fileName.isEmpty else { return }
        var map = loadMapWithMigration()
        map[fileName] = date.timeIntervalSince1970
        saveMap(pruneToLimit(map, limit: maxEntries))
    }

    /// 最後に使った音のファイル名（履歴中の最新）。未使用なら nil。
    /// #6 の `LastUsedSound.fileName` 相当。
    static var lastUsedFileName: String? {
        let map = loadMapWithMigration()
        return map.max(by: { $0.value < $1.value })?.key
    }

    /// 最近使った音を新しい順に最大 `limit` 件返す。
    /// `existingFileNames` に含まれない fileName は除外する（削除済み音を表示から自然に消すため）。
    static func recentFileNames(limit: Int, existingFileNames: Set<String>) -> [String] {
        let map = loadMapWithMigration()
        return Array(
            sortedNewestFirst(map)
                .map(\.fileName)
                .filter { existingFileNames.contains($0) }
                .prefix(limit)
        )
    }

    /// テスト/リセット用に履歴を消去する。
    static func clear() {
        AppGroup.userDefaults.removeObject(forKey: mapKey)
        AppGroup.userDefaults.removeObject(forKey: legacySingleKey)
    }

    // MARK: - Pure helpers（ユニットテスト対象）

    /// マップを新しい順（日時降順）の (fileName, date) 配列に変換する。純粋関数。
    static func sortedNewestFirst(_ map: [String: TimeInterval]) -> [(fileName: String, date: Date)] {
        map
            .map { (fileName: $0.key, date: Date(timeIntervalSince1970: $0.value)) }
            .sorted { $0.date > $1.date }
    }

    /// マップを新しい順に保ちつつ `limit` 件に切り詰める。純粋関数。
    static func pruneToLimit(_ map: [String: TimeInterval], limit: Int) -> [String: TimeInterval] {
        guard map.count > limit, limit >= 0 else { return map }
        let kept = Set(sortedNewestFirst(map).prefix(limit).map(\.fileName))
        return map.filter { kept.contains($0.key) }
    }

    // MARK: - Persistence

    private static func loadMapWithMigration() -> [String: TimeInterval] {
        // 新フォーマットが存在すればそのまま返す
        if let existing = AppGroup.userDefaults.dictionary(forKey: mapKey) as? [String: TimeInterval] {
            return existing
        }
        // 初回マイグレーション: #6 の単一値を履歴に取り込む
        if let legacy = AppGroup.userDefaults.string(forKey: legacySingleKey), !legacy.isEmpty {
            let migrated: [String: TimeInterval] = [legacy: Date().timeIntervalSince1970]
            AppGroup.userDefaults.set(migrated, forKey: mapKey)
            AppGroup.userDefaults.removeObject(forKey: legacySingleKey)
            return migrated
        }
        return [:]
    }

    private static func saveMap(_ map: [String: TimeInterval]) {
        AppGroup.userDefaults.set(map, forKey: mapKey)
    }
}
