import Foundation

/// お問い合わせに添付する診断情報の組み立て（#255）。
///
/// 音・動画のファイル名と表示名、アラームのラベルは **絶対に入れない**。
/// 音は「音1」「音2」…の番号に置き換える。
enum DiagnosticsReportBuilder {

    static let schemaVersion = 1
    static let historyLimit = 200

    /// 診断 JSON に残さないキー（履歴の取り込み時にも再帰的に落とす）。
    private static let deniedKeys: Set<String> = [
        "name", "names", "label", "labels", "title", "titles",
        "file_name", "file_names", "filename", "filenames",
        "sound_name", "sound_names", "sound_file_name", "sound_file_names",
        "display_name", "display_names", "playlist_name", "playlist_names"
    ]

    struct SoundMeasurement: Equatable, Sendable {
        let lufs: Double?
        let format: String

        init(lufs: Double?, format: String) {
            self.lufs = lufs
            self.format = format
        }
    }

    static func makeJSON(
        generatedAt: Date = Date(),
        timeZone: TimeZone = .current,
        appVersion: String,
        build: String,
        osVersion: String,
        deviceModel: String,
        localeIdentifier: String,
        alarmKitAuthorization: String,
        alarmKitRegisteredCount: Int?,
        alarms: [AlarmEntry],
        sounds: [AlarmSound],
        measurements: [UUID: SoundMeasurement],
        historyLines: [String],
        postHogDistinctID: String?,
        audioOutputs: [String]
    ) -> Data {
        let object = makeObject(
            generatedAt: generatedAt,
            timeZone: timeZone,
            appVersion: appVersion,
            build: build,
            osVersion: osVersion,
            deviceModel: deviceModel,
            localeIdentifier: localeIdentifier,
            alarmKitAuthorization: alarmKitAuthorization,
            alarmKitRegisteredCount: alarmKitRegisteredCount,
            alarms: alarms,
            sounds: sounds,
            measurements: measurements,
            historyLines: historyLines,
            postHogDistinctID: postHogDistinctID,
            audioOutputs: audioOutputs
        )
        return (try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        )) ?? Data("{}".utf8)
    }

    static func makeObject(
        generatedAt: Date = Date(),
        timeZone: TimeZone = .current,
        appVersion: String,
        build: String,
        osVersion: String,
        deviceModel: String,
        localeIdentifier: String,
        alarmKitAuthorization: String,
        alarmKitRegisteredCount: Int?,
        alarms: [AlarmEntry],
        sounds: [AlarmSound],
        measurements: [UUID: SoundMeasurement],
        historyLines: [String],
        postHogDistinctID: String?,
        audioOutputs: [String]
    ) -> [String: Any] {
        var soundNumberByFileName: [String: Int] = [:]
        let soundObjects: [[String: Any]] = sounds.enumerated().map { index, sound in
            let number = index + 1
            soundNumberByFileName[sound.fileName] = number
            let measurement = measurements[sound.id]
            var object: [String: Any] = [
                "number": number,
                "is_preset": sound.isPreset,
                "format": measurement?.format ?? fileExtension(sound.fileName)
            ]
            object["duration_seconds"] = optionalJSON(sound.durationSeconds.map(roundOneDecimal))
            object["lufs"] = optionalJSON(measurement?.lufs.map(roundOneDecimal))
            object["lufs_at_import"] = optionalJSON(sound.lufsAtImport.map(roundOneDecimal))
            object["gain_db"] = optionalJSON(sound.gainDbAtImport.map(roundOneDecimal))
            return object
        }

        let alarmObjects: [[String: Any]] = alarms.enumerated().map { index, alarm in
            var object: [String: Any] = [
                "number": index + 1,
                "time": String(format: "%02d:%02d", alarm.hour, alarm.minute),
                "repeat_weekdays": alarm.repeatWeekdays.sorted(),
                "enabled": alarm.isEnabled,
                "snooze_minutes": alarm.snoozeMinutes,
                "skips_holidays": alarm.skipsHolidays,
                "skip_dates_count": alarm.skipDates.count,
                "holiday_ring_overrides_count": alarm.holidayRingOverrides.count,
                "fade_in_seconds": alarm.fadeIn.rawValue,
                "uses_playlist": alarm.playlistID != nil
            ]
            object["backup_minutes"] = optionalJSON(alarm.backupMinutes)
            // ファイル名は出さず、音の番号だけを出す
            if alarm.playlistID == nil {
                object["sound_number"] = optionalJSON(soundNumberByFileName[alarm.soundFileName])
            }
            return object
        }

        let history = historyLines
            .suffix(historyLimit)
            .compactMap(parseAndSanitizeHistoryLine)

        var app: [String: Any] = [
            "version": appVersion,
            "build": build,
            "os_version": osVersion,
            "device_model": deviceModel,
            "locale": localeIdentifier
        ]
        app["diagnostics_schema"] = schemaVersion

        var alarmKit: [String: Any] = ["authorization": alarmKitAuthorization]
        alarmKit["registered_count"] = optionalJSON(alarmKitRegisteredCount)

        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]

        var object: [String: Any] = [
            "schema_version": schemaVersion,
            "generated_at": formatter.string(from: generatedAt),
            "time_zone": timeZone.identifier,
            "time_zone_offset_minutes": timeZone.secondsFromGMT(for: generatedAt) / 60,
            "app": app,
            "alarm_kit": alarmKit,
            "alarms": alarmObjects,
            "sounds": soundObjects,
            "audio_outputs": audioOutputs,
            "history": history
        ]
        object["posthog_distinct_id"] = optionalJSON(postHogDistinctID)
        return object
    }

    // MARK: - Privacy

    private static func parseAndSanitizeHistoryLine(_ line: String) -> Any? {
        guard let data = line.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data)
        else { return nil }
        return sanitize(parsed)
    }

    /// ファイル名・表示名・ラベルらしきキーを再帰的に落とす。
    private static func sanitize(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, child) in dictionary {
                let normalized = key.lowercased()
                guard !deniedKeys.contains(normalized),
                      !normalized.contains("file_name"),
                      !normalized.contains("filename"),
                      !normalized.contains("sound_name")
                else { continue }
                result[key] = sanitize(child)
            }
            return result
        }
        if let array = value as? [Any] {
            return array.map(sanitize)
        }
        return value
    }

    private static func fileExtension(_ fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return ext.isEmpty ? "unknown" : ext
    }

    private static func roundOneDecimal(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    /// `[String: Any]` に Optional をそのまま入れると JSON にできなくなるため NSNull にする。
    private static func optionalJSON<T>(_ value: T?) -> Any {
        value ?? NSNull()
    }
}
