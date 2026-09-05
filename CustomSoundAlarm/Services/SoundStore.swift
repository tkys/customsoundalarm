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
        var sound = sound
        // 追加時に秒数を記録する（起動のたびに全ファイルを AVURLAsset で読まない・#68）
        if !sound.isPreset && sound.durationSeconds == nil {
            sound.durationSeconds = AudioConverter.shared.measureDurationSeconds(fileName: sound.fileName)
        }
        sounds.append(sound)
        save()
    }

    /// 既存のカスタム音源のうち秒数が未記録のものを一度だけ補完して永続化する。
    /// バージョンアップで `durationSeconds` が追加される前にインポートされた音源向け（#17 罠1対応）。
    /// 計測済みの音源は対象外なので、起動のたびに全ファイルを読むことはない。
    /// - Returns: 補完して保存したか（ユーザープロパティの再送判定用）
    @discardableResult
    func backfillMissingDurations() -> Bool {
        var changed = false
        for index in sounds.indices
        where !sounds[index].isPreset && sounds[index].durationSeconds == nil {
            if let seconds = AudioConverter.shared.measureDurationSeconds(fileName: sounds[index].fileName) {
                sounds[index].durationSeconds = seconds
                changed = true
            }
        }
        if changed { save() }
        return changed
    }

    /// カスタム音源のうち秒数が未記録のものがあるか（バックフィル要否判定）
    func hasMissingDurations() -> Bool {
        sounds.contains { !$0.isPreset && $0.durationSeconds == nil }
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
            // サムネイルも一緒に消す（#86）
            if let thumbnailFileName = sound.thumbnailFileName {
                SoundThumbnailStore.shared.delete(fileName: thumbnailFileName)
            }
        } else {
            // プリセット削除を記録し、再起動時に復活しないようにする（罠1）
            var dismissed = AppGroup.dismissedPresetFileNames
            dismissed.insert(sound.fileName)
            AppGroup.dismissedPresetFileNames = dismissed
        }
        save()
    }

    /// ファイル名からサウンドの表示名を返す。
    /// 未登録のファイル名の場合はローカライズされた「見つかりません」文言を返し、
    /// 生ファイル名（UUID.caf）が表示されることを防ぐ。
    func displayName(for fileName: String) -> String {
        if fileName.isEmpty { return "" }
        return sounds.first { $0.fileName == fileName }?.name
            ?? String(localized: "sound_missing")
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

                    // サムネイル生成（#86）: 動画はフレーム、音声はアートワーク
                    let thumbnailFileName: String?
                    if isVideo, let frame = await SoundThumbnailStore.shared.bestVideoFrame(from: audioFile) {
                        thumbnailFileName = SoundThumbnailStore.shared.save(frame)
                    } else if let artwork = await SoundThumbnailStore.shared.artwork(from: audioFile) {
                        thumbnailFileName = SoundThumbnailStore.shared.save(artwork)
                    } else {
                        thumbnailFileName = nil
                    }

                    let sound = AlarmSound(name: pending.displayName, fileName: cafName, thumbnailFileName: thumbnailFileName)
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

    /// プリセット音源の定義リスト。
    /// 音源追加手順:
    /// 1. CAF ファイル（PCM 16-bit / 44.1kHz / mono / 30秒以内 / 商用利用可）を
    ///    CustomSoundAlarm/Resources/Sounds/ に配置
    /// 2. 以下のリストに (fileName, labelKey) を追加
    /// 3. Localizable.strings（en/ja）に labelKey の翻訳を追加
    /// 4. docs/adding-preset-sounds.md も参照
    static let presetDefinitions: [PresetRegistration.Definition] = [
        PresetRegistration.Definition(fileName: "PresetMarimba.caf", labelKey: "preset_marimba"),
        PresetRegistration.Definition(fileName: "PresetBell.caf", labelKey: "preset_bell"),
        PresetRegistration.Definition(fileName: "PresetCrescendo.caf", labelKey: "preset_crescendo"),
        PresetRegistration.Definition(fileName: "PresetBeep.caf", labelKey: "preset_beep"),
        PresetRegistration.Definition(fileName: "PresetAscending.caf", labelKey: "preset_ascending"),
        PresetRegistration.Definition(fileName: "PresetDualTone.caf", labelKey: "preset_dual_tone"),
        PresetRegistration.Definition(fileName: "PresetMusicBox.caf", labelKey: "preset_music_box"),
    ]

    /// プリセット音源を登録（未登録かつ未削除のもののみ）
    private func registerPresets() {
        let existing = Set(sounds.map(\.fileName))
        let dismissed = AppGroup.dismissedPresetFileNames
        let toRegister = PresetRegistration.presetsToRegister(
            definitions: SoundStore.presetDefinitions,
            existingFileNames: existing,
            dismissedFileNames: dismissed
        )
        for def in toRegister {
            add(AlarmSound(
                name: String(localized: String.LocalizationValue(def.labelKey)),
                fileName: def.fileName,
                isPreset: true
            ))
        }
        if !toRegister.isEmpty {
            logger.info("Registered \(toRegister.count) preset sound(s)")
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

