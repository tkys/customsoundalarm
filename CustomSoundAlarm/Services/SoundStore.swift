import Foundation
import os

/// アラーム音の管理（保存・読み込み・削除）
/// UserDefaultsベースのシンプルな永続化
@Observable
@MainActor
final class SoundStore {
    static let shared = SoundStore()

    private let logger = Logger(subsystem: "com.tkysdev.customsoundalarm", category: "SoundStore")
    private let key = "saved_alarm_sounds"

    private(set) var sounds: [AlarmSound] = []

    private init() {
        load()
    }

    func add(_ sound: AlarmSound) {
        sounds.append(sound)
        save()
    }

    func remove(_ sound: AlarmSound) {
        sounds.removeAll { $0.id == sound.id }
        // CAFファイルも削除
        try? AudioConverter.shared.deleteSound(fileName: sound.fileName)
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([AlarmSound].self, from: data) else {
            return
        }
        sounds = decoded
        logger.info("Loaded \(self.sounds.count) sounds")
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sounds) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
