import Foundation
import os

/// アラーム設定の管理（保存・読み込み・削除）
@Observable
@MainActor
final class AlarmStore {
    static let shared = AlarmStore()

    private let logger = Logger(subsystem: "com.tkysdev.customsoundalarm", category: "AlarmStore")
    private let key = "saved_alarms"

    private(set) var alarms: [AlarmEntry] = []

    /// データ変更検知用（reload 前後で比較し、変化があった場合のみ sync するために使用）
    private(set) var contentHash: Int = 0

    private init() {
        load()
    }

    func add(_ alarm: AlarmEntry) {
        alarms.append(alarm)
        save()
    }

    func update(_ alarm: AlarmEntry) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        alarms[index] = alarm
        save()
    }

    func remove(_ alarm: AlarmEntry) {
        alarms.removeAll { $0.id == alarm.id }
        save()
    }

    func toggleEnabled(_ alarm: AlarmEntry) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        alarms[index].isEnabled.toggle()
        save()
    }

    /// 外部変更（Share Extension等）後にデータを再読み込み
    /// - Returns: データが変更されたかどうか
    @discardableResult
    func reload() -> Bool {
        let oldHash = contentHash
        load()
        return contentHash != oldHash
    }

    // MARK: - Persistence

    private func load() {
        guard let data = AppGroup.userDefaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([AlarmEntry].self, from: data) else {
            return
        }
        alarms = decoded
        contentHash = data.hashValue
        logger.info("Loaded \(self.alarms.count) alarms")
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(alarms) else { return }
        AppGroup.userDefaults.set(data, forKey: key)
        contentHash = data.hashValue
    }
}
