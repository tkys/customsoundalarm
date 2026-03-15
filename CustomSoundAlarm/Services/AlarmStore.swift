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

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([AlarmEntry].self, from: data) else {
            return
        }
        alarms = decoded
        logger.info("Loaded \(self.alarms.count) alarms")
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(alarms) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
