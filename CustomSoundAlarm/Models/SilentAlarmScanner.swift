import Foundation

/// 既存アラームの音が無音・ほぼ無音かを起動時に調べる（#256）。
enum SilentAlarmScanner {
    static func silentAlarmIDs(
        entries: [AlarmEntry],
        soundsDirectory: URL,
        measure: (URL) -> LoudnessMeter.Measurement?
    ) -> Set<UUID> {
        var cache: [String: LoudnessMeter.Measurement?] = [:]
        var result: Set<UUID> = []

        for entry in entries {
            guard entry.playlistID == nil, !entry.soundFileName.isEmpty else { continue }
            let url = soundsDirectory.appendingPathComponent(entry.soundFileName)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            let measurement: LoudnessMeter.Measurement?
            if let cached = cache[entry.soundFileName] {
                measurement = cached
            } else {
                measurement = measure(url)
                cache[entry.soundFileName] = measurement
            }

            if let measurement {
                if SilentSoundLogic.warningLevel(
                    lufs: measurement.lufs,
                    peakDb: measurement.peakDb
                ) != .ok {
                    result.insert(entry.id)
                }
            } else {
                result.insert(entry.id)
            }
        }
        return result
    }
}
