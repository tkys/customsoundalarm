import Foundation

/// 大きくした版の準備中に見せる進み具合（#297）。
/// 「試す」を押したときに作り始めるのではなく、先に作り始めた同じ処理につなぐ。
@MainActor
@Observable
final class LoudVariantPreparation {
    let sourceFileName: String
    private(set) var progress: Double = 0
    private(set) var isRunning = true
    private(set) var result: String?
    fileprivate var task: Task<Void, Never>?

    fileprivate init(sourceFileName: String) {
        self.sourceFileName = sourceFileName
    }

    fileprivate func updateProgress(_ value: Double) {
        progress = max(progress, min(1, value))
    }

    fileprivate func finish(fileName: String?) {
        result = fileName
        progress = 1
        isRunning = false
        task = nil
    }

    /// 生成の完了まで待つ（呼び出し側がキャンセルされても生成は止めない）。
    fileprivate func wait() async {
        if let task {
            await task.value
        }
    }
}

/// 大きくした版の生成・再利用・後片付け（#119）。
@MainActor
enum BackupLoudVariantService {

    private static var soundsDirectory: URL {
        AudioConverter.shared.soundsDirectory
    }

    /// 生成中のジョブ（音源ファイル名ごと）
    private static var preparations: [String: LoudVariantPreparation] = [:]

    /// 先に大きくした版を作り始める対象（#297）。
    /// 寝過ごし防止がオフ、または鳴らす音が無いときは nil。
    static func sourceToPrepare(
        backupMinutes: Int?,
        resolvedSourceFileName: String?
    ) -> String? {
        guard backupMinutes != nil,
              let sourceFileName = resolvedSourceFileName,
              !sourceFileName.isEmpty else { return nil }
        return sourceFileName
    }

    /// 既に存在する大きくした版のファイル名（現行の生成方式のものだけ）
    static func existingVariantFileName(for sourceFileName: String) -> String? {
        guard let variant = BackupSoundResolver.variantFileName(for: sourceFileName) else {
            return nil
        }
        let url = soundsDirectory.appendingPathComponent(variant)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard !LoudVariantMetadata.shouldRegenerate(metadata(for: variant)) else {
            return nil
        }
        return variant
    }

    /// 最終アラームで使う音（大きくした版 or 予備音）
    static func resolvedSoundFileName(for entry: AlarmEntry) -> String {
        resolvedSoundFileName(forSourceFileName: entry.soundFileName)
    }

    /// 元の音ファイル名から、大きくした版 or 予備音を解決する。
    /// プレイリストのフォールバック（存在する最初の曲）でも使う（#151）。
    static func resolvedSoundFileName(forSourceFileName sourceFileName: String) -> String {
        BackupSoundResolver.resolve(
            sourceFileName: sourceFileName,
            availableVariantFileName: existingVariantFileName(for: sourceFileName),
            fallbackFileName: BackupAlarmSound.fileName
        )
    }

    /// 生成中なら、そのジョブを返す（「試す」の進み具合に使う）。
    static func preparation(for sourceFileName: String) -> LoudVariantPreparation? {
        guard let job = preparations[sourceFileName], job.isRunning else { return nil }
        return job
    }

    /// 裏で大きくした版を作り始める（#297）。
    /// すでにある・作れない・生成中なら新しく始めない（生成中ならそのジョブを返す）。
    @discardableResult
    static func prepareInBackground(for sourceFileName: String) -> LoudVariantPreparation? {
        guard BackupSoundResolver.variantFileName(for: sourceFileName) != nil else {
            return nil
        }
        #if DEBUG
        if isUITestSlowPreparation {
            clearLoudVariantsForUITestIfNeeded()
        }
        #endif
        if existingVariantFileName(for: sourceFileName) != nil { return nil }
        if let job = preparation(for: sourceFileName) { return job }

        let job = LoudVariantPreparation(sourceFileName: sourceFileName)
        preparations[sourceFileName] = job
        job.task = Task {
            #if DEBUG
            // UIテスト用: 準備中の見た目を確かめられるよう、生成前に待つ
            if Self.isUITestSlowPreparation {
                for step in 1...60 {
                    try? await Task.sleep(for: .milliseconds(500))
                    job.updateProgress(Double(step) / 60)
                }
            }
            #endif
            let fileName = await generateVariant(for: sourceFileName) { value in
                Task { @MainActor in
                    job.updateProgress(value)
                }
            }
            job.finish(fileName: fileName)
            if preparations[sourceFileName] === job {
                preparations[sourceFileName] = nil
            }
        }
        return job
    }

    #if DEBUG
    private static var isUITestSlowPreparation: Bool {
        CommandLine.arguments.contains("-uitest-slow-loud-variant")
    }

    private static var didClearLoudVariantsForUITest = false

    /// UIテスト用: 前回の実行で残った大きくした版を消し、準備中の状態を作れるようにする。
    private static func clearLoudVariantsForUITestIfNeeded() {
        guard !didClearLoudVariantsForUITest else { return }
        didClearLoudVariantsForUITest = true
        let files = (try? FileManager.default.contentsOfDirectory(
            at: soundsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        for file in files where file.lastPathComponent.contains(".loud.") {
            try? FileManager.default.removeItem(at: file)
        }
    }
    #endif

    /// 大きくした版を用意する。既にあれば再生成しない。
    /// 生成できなければ nil（呼び出し側は予備音にフォールバック）。
    /// 先に裏で作り始めていれば、その処理の完了を待つ（#297）。
    static func ensureVariant(for sourceFileName: String) async -> String? {
        guard let variant = BackupSoundResolver.variantFileName(for: sourceFileName) else {
            return nil
        }
        if existingVariantFileName(for: sourceFileName) != nil {
            return variant
        }
        guard let job = prepareInBackground(for: sourceFileName) else {
            return existingVariantFileName(for: sourceFileName)
        }
        await job.wait()
        return job.result
    }

    private static func generateVariant(
        for sourceFileName: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async -> String? {
        guard let variant = BackupSoundResolver.variantFileName(for: sourceFileName) else {
            return nil
        }
        guard let source = sourceInfo(for: sourceFileName) else {
            AnalyticsService.shared.capture(.backupLoudVariantFailed(reason: .sourceMissing))
            return nil
        }

        let outputURL = soundsDirectory.appendingPathComponent(variant)
        let startedAt = Date()
        do {
            let result = try await Task.detached(priority: .utility) {
                try LoudVariantGenerator.generate(
                    sourceURL: source.url,
                    outputURL: outputURL,
                    sourceFileName: sourceFileName,
                    source: source.source,
                    progress: progress
                )
            }.value
            writeMetadata(for: variant)
            AnalyticsService.shared.capture(.backupLoudVariantGenerated(
                gainDbBucket: LoudVariantGenerator.gainDbBucket(result.gainDb),
                durationBucket: LoudVariantGenerator.durationBucket(result.durationSeconds),
                source: result.source,
                outputLufsBucket: LoudnessMeter.bucket(forLufs: result.outputLufs),
                durationMsBucket: LoudVariantGenerator.generationDurationMsBucket(
                    Int(Date().timeIntervalSince(startedAt) * 1000)
                )
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
        try? FileManager.default.removeItem(
            at: soundsDirectory.appendingPathComponent(metadataFileName(for: variant))
        )
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

        for file in files {
            let name = file.lastPathComponent
            guard name.hasSuffix(".loud.caf") || name.hasSuffix(".loud.json") else { continue }
            let base = name
                .replacingOccurrences(of: ".loud.caf", with: "")
                .replacingOccurrences(of: ".loud.json", with: "")
                + ".caf"
            let isUsed = used.contains(base) && availableSourceFileNames.contains(base)
            if !isUsed {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: - Metadata

    static func metadataFileName(for variantFileName: String) -> String {
        variantFileName.replacingOccurrences(of: ".caf", with: ".json")
    }

    static func metadata(for variantFileName: String) -> LoudVariantMetadata? {
        let url = soundsDirectory.appendingPathComponent(metadataFileName(for: variantFileName))
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LoudVariantMetadata.self, from: data)
    }

    private static func writeMetadata(for variantFileName: String) {
        let metadata = LoudVariantMetadata(version: LoudVariantGenerator.version)
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        let url = soundsDirectory.appendingPathComponent(metadataFileName(for: variantFileName))
        try? data.write(to: url)
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

    /// 生成にかかった時間（ミリ秒）→ 区分（#297）。
    /// 寝過ごし防止の「試す」を押してから鳴るまでの待ち時間の目安。
    static func generationDurationMsBucket(_ milliseconds: Int) -> String {
        switch milliseconds {
        case ..<500: return "under_500ms"
        case ..<1000: return "500ms_1s"
        case ..<3000: return "1_3s"
        case ..<10000: return "3_10s"
        case ..<30000: return "10_30s"
        default: return "over_30s"
        }
    }
}
