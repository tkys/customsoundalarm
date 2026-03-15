import Foundation
import os

/// アラーム音の管理（保存・読み込み・削除）
/// App Group UserDefaultsで永続化（Share Extensionと共有）
@Observable
@MainActor
final class SoundStore {
    static let shared = SoundStore()

    private let logger = Logger(subsystem: "com.tkysdev.customsoundalarm", category: "SoundStore")
    private let key = "saved_alarm_sounds"

    private(set) var sounds: [AlarmSound] = []

    private init() {
        migrateFromStandard()
        load()
    }

    func add(_ sound: AlarmSound) {
        sounds.append(sound)
        save()
    }

    func remove(_ sound: AlarmSound) {
        sounds.removeAll { $0.id == sound.id }
        if !sound.isPreset {
            try? AudioConverter.shared.deleteSound(fileName: sound.fileName)
        }
        save()
    }

    /// ファイル名からサウンドの表示名を返す
    func displayName(for fileName: String) -> String {
        if fileName.isEmpty { return "" }
        return sounds.first { $0.fileName == fileName }?.name ?? fileName
    }

    /// Share Extensionが追加したサウンドを取り込む
    func importFromStaging() {
        let staging = AppGroup.stagingDirectory
        let fm = FileManager.default

        guard let files = try? fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil) else {
            return
        }

        // メタデータファイル(.json)を読み込み
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let pending = try? JSONDecoder().decode(PendingSoundImport.self, from: data) else {
                continue
            }

            let audioFile = staging.appendingPathComponent(pending.stagedFileName)
            guard fm.fileExists(atPath: audioFile.path) else { continue }

            // CAFに変換してLibrary/Soundsへ
            Task {
                do {
                    let cafName = try await AudioConverter.shared.convertToCAF(
                        from: audioFile,
                        outputName: UUID().uuidString
                    )
                    let sound = AlarmSound(name: pending.displayName, fileName: cafName)
                    add(sound)
                    // ステージングをクリーンアップ
                    try? fm.removeItem(at: file)
                    try? fm.removeItem(at: audioFile)
                    logger.info("Imported from staging: \(pending.displayName)")
                } catch {
                    logger.error("Failed to import from staging: \(error.localizedDescription)")
                }
            }
        }
    }

    /// フォアグラウンド復帰時に再読み込み
    func reload() {
        load()
        importFromStaging()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = AppGroup.userDefaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([AlarmSound].self, from: data) else {
            return
        }
        sounds = decoded
        logger.info("Loaded \(self.sounds.count) sounds")
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sounds) else { return }
        AppGroup.userDefaults.set(data, forKey: key)
    }

    /// 旧UserDefaults.standardからの一回限りマイグレーション
    private func migrateFromStandard() {
        let oldKey = key
        guard let oldData = UserDefaults.standard.data(forKey: oldKey),
              AppGroup.userDefaults.data(forKey: key) == nil else {
            return
        }
        AppGroup.userDefaults.set(oldData, forKey: key)
        UserDefaults.standard.removeObject(forKey: oldKey)
        logger.info("Migrated sounds from standard UserDefaults to app group")
    }
}

