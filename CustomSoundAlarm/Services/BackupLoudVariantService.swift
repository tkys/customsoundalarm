import Foundation

/// 大きくした版の生成・再利用・後片付け（#119）。
@MainActor
enum BackupLoudVariantService {

    private static var soundsDirectory: URL {
        AudioConverter.shared.soundsDirectory
    }

    /// 既に存在する大きくした版のファイル名（無ければ nil）
    static func existingVariantFileName(for sourceFileName: String) -> String? {
        guard let variant = BackupSoundResolver.variantFileName(for: sourceFileName) else {
            return nil
        }
        let url = soundsDirectory.appendingPathComponent(variant)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return variant
    }

    /// 最終アラームで使う音（大きくした版 or 予備音）
    static func resolvedSoundFileName(for entry: AlarmEntry) -> String {
        BackupSoundResolver.resolve(
            sourceFileName: entry.soundFileName,
            availableVariantFileName: existingVariantFileName(for: entry.soundFileName),
            fallbackFileName: BackupAlarmSound.fileName
        )
    }

    /// 大きくした版を用意する。既にあれば再生成しない。
    /// 生成できなければ nil（呼び出し側は予備音にフォールバック）。
    static func ensureVariant(for sourceFileName: String) async -> String? {
        guard let variant = BackupSoundResolver.variantFileName(for: sourceFileName) else {
            return nil
        }
        if existingVariantFileName(for: sourceFileName) != nil {
            return variant
        }
        guard let source = sourceInfo(for: sourceFileName) else {
            AnalyticsService.shared.capture(.backupLoudVariantFailed(reason: .sourceMissing))
            return nil
        }

        let outputURL = soundsDirectory.appendingPathComponent(variant)
        do {
            let result = try await Task.detached(priority: .utility) {
                try LoudVariantGenerator.generate(
                    sourceURL: source.url,
                    outputURL: outputURL,
                    sourceFileName: sourceFileName,
                    source: source.source
                )
            }.value
            AnalyticsService.shared.capture(.backupLoudVariantGenerated(
                gainDbBucket: LoudVariantGenerator.gainDbBucket(result.gainDb),
                durationBucket: LoudVariantGenerator.durationBucket(result.durationSeconds),
                source: result.source
            ))
            return result.fileName
        } catch let error as LoudVariantGenerator.GenerateError {
            AnalyticsService.shared.capture(.backupLoudVariantFailed(reason: error))
            return nil
        } catch {
            AnalyticsService.shared.capture(.backupLoudVariantFailed(reason: .renderFailed))
            return nil
        }
    }

    /// 元の音源を削除したときに、大きくした版も削除する。
    static func deleteVariant(for sourceFileName: String) {
        guard let variant = BackupSoundResolver.variantFileName(for: sourceFileName) else {
            return
        }
        try? FileManager.default.removeItem(at: soundsDirectory.appendingPathComponent(variant))
    }

    /// どのアラームにも使われていない（または元音源が消えた）大きくした版を削除する。
    /// 起動時に呼ぶ。
    static func cleanupUnusedVariants(
        entries: [AlarmEntry],
        availableSourceFileNames: Set<String>
    ) {
        let used = Set(
            entries
                .filter { $0.isEnabled && $0.backupMinutes != nil && !$0.soundFileName.isEmpty }
                .map(\.soundFileName)
        )
        let files = (try? FileManager.default.contentsOfDirectory(
            at: soundsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []

        for file in files where file.lastPathComponent.hasSuffix(".loud.caf") {
            let base = file.lastPathComponent
                .replacingOccurrences(of: ".loud.caf", with: "")
                + ".caf"
            let isUsed = used.contains(base) && availableSourceFileNames.contains(base)
            if !isUsed {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: - Source resolution

    struct SourceInfo {
        let url: URL
        let source: LoudVariantGenerator.Source
    }

    static func sourceInfo(for fileName: String) -> SourceInfo? {
        guard !fileName.isEmpty else { return nil }
        let base = fileName.replacingOccurrences(of: ".caf", with: "")
        if let bundleURL = Bundle.main.url(forResource: base, withExtension: "caf") {
            return SourceInfo(url: bundleURL, source: .preset)
        }
        let url = soundsDirectory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return SourceInfo(url: url, source: .imported)
    }
}

// MARK: - Analytics buckets

extension LoudVariantGenerator {
    static func gainDbBucket(_ gainDb: Double) -> String {
        if gainDb <= 0 { return "0" }
        if gainDb <= 6 { return "0~6" }
        if gainDb <= 12 { return "6~12" }
        if gainDb <= 20 { return "12~20" }
        return "20~30"
    }

    static func durationBucket(_ seconds: Double) -> String {
        if seconds < 30 { return "under_30s" }
        if seconds < 60 { return "30_60s" }
        return "60s"
    }
}
