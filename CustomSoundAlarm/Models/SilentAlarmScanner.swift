import Foundation

/// 既存アラームの音が無音・ほぼ無音かを調べる（#256）。
///
/// 取り込んだ音のファイルはあとから変わらないので、ファイル名ごとの結果を
/// 呼び出し側（`AppGroup`）に保存し、まだ測っていないファイルだけを測る。
/// 計測できなかったファイルは警告しない（誤検知より見逃しを選ぶ）。
enum SilentAlarmScanner {

    struct Result: Equatable {
        /// 警告を出すアラームと、そのレベル。
        let levels: [UUID: SilentSoundLevel]
        /// ファイル名 → レベル（"ok" も含む）。次回起動時に再利用する。
        let cache: [String: String]
    }

    static func scan(
        entries: [AlarmEntry],
        soundsDirectory: URL,
        cached: [String: String],
        measure: (URL) -> LoudnessMeter.Measurement?
    ) -> Result {
        var cache = cached
        var levels: [UUID: SilentSoundLevel] = [:]

        for entry in entries {
            guard entry.playlistID == nil, !entry.soundFileName.isEmpty else { continue }
            let fileName = entry.soundFileName

            let level: SilentSoundLevel
            if let cachedRaw = cache[fileName] {
                level = SilentSoundLevel(rawValue: cachedRaw) ?? .ok
            } else {
                let url = soundsDirectory.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: url.path) {
                    if let measurement = measure(url) {
                        level = SilentSoundLogic.warningLevel(
                            lufs: measurement.lufs,
                            peakDb: measurement.peakDb
                        )
                    } else {
                        // 計測できない = 警告しない。次回も測り直さない。
                        level = .ok
                    }
                    cache[fileName] = level.rawValue
                } else {
                    // ファイルが見つからないだけなら、あとから現れる可能性があるので保存しない。
                    level = .ok
                }
            }

            if level != .ok {
                levels[entry.id] = level
            }
        }
        return Result(levels: levels, cache: cache)
    }
}
