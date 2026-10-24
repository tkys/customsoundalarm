import Foundation

/// サウンドの大きさ区分をファイル名ごとにキャッシュする（#109 C）。
/// 画面を開き直すたびにファイルを読み直さない。
@Observable
@MainActor
final class SoundLoudnessStore {
    static let shared = SoundLoudnessStore()

    @ObservationIgnored private var levels: [String: SoundLoudness.Level] = [:]
    @ObservationIgnored private var unreadableFileNames: Set<String> = []
    @ObservationIgnored private var tasks: [String: Task<SoundLoudness.Measurement?, Never>] = [:]

    private init() {}

    /// ファイル名の大きさ区分を返す（キャッシュ優先）。
    func level(for fileName: String) async -> SoundLoudness.Level? {
        guard !fileName.isEmpty else { return nil }
        if let cached = levels[fileName] { return cached }
        if unreadableFileNames.contains(fileName) { return nil }

        if let task = tasks[fileName] {
            return await finish(task: task, fileName: fileName)
        }

        guard let url = resolveURL(for: fileName) else {
            unreadableFileNames.insert(fileName)
            return nil
        }

        let task = Task.detached(priority: .utility) {
            SoundLoudness.measure(fileURL: url)
        }
        tasks[fileName] = task
        return await finish(task: task, fileName: fileName)
    }

    private func finish(
        task: Task<SoundLoudness.Measurement?, Never>,
        fileName: String
    ) async -> SoundLoudness.Level? {
        let measurement = await task.value
        tasks[fileName] = nil
        guard let measurement else {
            unreadableFileNames.insert(fileName)
            return nil
        }
        let level = SoundLoudness.level(forRmsDb: measurement.rmsDb)
        levels[fileName] = level
        return level
    }

    private func resolveURL(for fileName: String) -> URL? {
        let resourceName = fileName.replacingOccurrences(of: ".caf", with: "")
        if let presetURL = Bundle.main.url(forResource: resourceName, withExtension: "caf") {
            return presetURL
        }
        let userURL = AudioConverter.shared.soundsDirectory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: userURL.path) else { return nil }
        return userURL
    }

    #if DEBUG
    /// テスト用: キャッシュを空にする
    func resetCache() {
        levels = [:]
        unreadableFileNames = []
        tasks = [:]
    }
    #endif
}
