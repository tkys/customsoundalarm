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
        registerPresets()
    }

    func add(_ sound: AlarmSound) {
        sounds.append(sound)
        save()
    }

    func rename(_ sound: AlarmSound, to newName: String) {
        guard let index = sounds.firstIndex(where: { $0.id == sound.id }) else { return }
        sounds[index].name = newName
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

        let jsonFiles = files.filter { $0.pathExtension == "json" }
        guard !jsonFiles.isEmpty else { return }

        logger.info("Found \(jsonFiles.count) pending imports in staging")

        for file in jsonFiles {
            guard let data = try? Data(contentsOf: file),
                  let pending = try? JSONDecoder().decode(PendingSoundImport.self, from: data) else {
                continue
            }

            let audioFile = staging.appendingPathComponent(pending.stagedFileName)
            guard fm.fileExists(atPath: audioFile.path) else { continue }

            // 動画の場合は先に音声抽出、その後CAF変換
            let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi"]
            let isVideo = videoExtensions.contains(audioFile.pathExtension.lowercased())

            Task {
                do {
                    var sourceForCAF = audioFile
                    var tempAudioURL: URL?

                    if isVideo {
                        let extracted = try await VideoAudioExtractor.shared.extractAudio(from: audioFile)
                        sourceForCAF = extracted
                        tempAudioURL = extracted
                    }

                    let cafName = try await AudioConverter.shared.convertToCAF(
                        from: sourceForCAF,
                        outputName: UUID().uuidString
                    )
                    let sound = AlarmSound(name: pending.displayName, fileName: cafName)
                    add(sound)
                    try? fm.removeItem(at: file)
                    try? fm.removeItem(at: audioFile)
                    if let tempAudioURL {
                        try? fm.removeItem(at: tempAudioURL)
                    }
                    logger.info("Imported from share: \(pending.displayName)")
                } catch {
                    logger.error("Import failed for \(pending.displayName): \(error.localizedDescription)")
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

    /// プリセット音源を登録（未登録時のみ）
    private func registerPresets() {
        if !sounds.contains(where: { $0.fileName == "PresetAlarm.caf" }) {
            add(AlarmSound(name: "ジャズ", fileName: "PresetAlarm.caf", isPreset: true))
        }
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

