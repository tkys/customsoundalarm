import Foundation

/// アラームの履歴計測（#241）。
///
/// PostHog に送る共通プロパティと、端末内にだけ残す JSON Lines を作る。
/// ラベル・音の名前・プレイリスト名は含めない。
struct AlarmListSnapshot: Equatable, Sendable {
    let onTimes: [String]
    let offTimes: [String]
}

struct AlarmEventContext: Equatable, Sendable {
    let alarmUID: String
    let alarmTime: String
    let repeatDays: String
    let localTime: String
    let localWeekday: Int
    let tzOffsetMin: Int
    var list: AlarmListSnapshot?
    var suggestionIndex: Int?
    var secondsToSave: Int?
    var prevAlarmTime: String?

    var properties: [String: Any] {
        var d: [String: Any] = [
            "alarm_uid": alarmUID,
            "alarm_time": alarmTime,
            "repeat_days": repeatDays,
            "local_time": localTime,
            "local_weekday": localWeekday,
            "tz_offset_min": tzOffsetMin,
            "history_schema": 1
        ]
        if let list {
            d["list_on_count"] = list.onTimes.count
            d["list_off_count"] = list.offTimes.count
            d["list_on_times"] = list.onTimes.joined(separator: ",")
            d["list_off_times"] = list.offTimes.joined(separator: ",")
        }
        if let suggestionIndex { d["suggestion_index"] = suggestionIndex }
        if let secondsToSave { d["seconds_to_save"] = secondsToSave }
        if let prevAlarmTime { d["prev_alarm_time"] = prevAlarmTime }
        return d
    }
}

enum AlarmHistoryLogic {
    static let listLimit = 20

    static func context(
        for entry: AlarmEntry,
        list: [AlarmEntry]? = nil,
        now: Date = Date(),
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) -> AlarmEventContext {
        AlarmEventContext(
            alarmUID: AlarmUIDStore.uid(for: entry.id, now: now),
            alarmTime: String(format: "%02d:%02d", entry.hour, entry.minute),
            repeatDays: entry.repeatWeekdays.sorted().map(String.init).joined(separator: ","),
            localTime: localTimeString(now, roundingToFiveMinutes: true, calendar: calendar, timeZone: timeZone),
            localWeekday: calendar.component(.weekday, from: now),
            tzOffsetMin: timeZone.secondsFromGMT(for: now) / 60
        )
    }

    static func listSnapshot(_ entries: [AlarmEntry]) -> AlarmListSnapshot {
        let on = entries.filter(\.isEnabled).map(\.timeString).sorted().prefix(listLimit)
        let off = entries.filter { !$0.isEnabled }.map(\.timeString).sorted().prefix(listLimit)
        return AlarmListSnapshot(onTimes: Array(on), offTimes: Array(off))
    }

    /// 5分単位に切り捨てた現地時刻（PostHog 用）。
    static func localTimeString(
        _ date: Date,
        roundingToFiveMinutes: Bool,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let rounded: Date
        if roundingToFiveMinutes {
            rounded = Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 300).rounded(.down) * 300)
        } else {
            rounded = date
        }
        var calendar = calendar
        calendar.timeZone = timeZone
        let comps = calendar.dateComponents([.hour, .minute], from: rounded)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }

    static func daysSinceCreated(
        alarmID: UUID,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let created = AlarmUIDStore.creationDate(for: alarmID, now: now)
        return max(0, calendar.dateComponents([.day], from: created, to: now).day ?? 0)
    }
}

/// アラームごとのランダム UID と初回発行日（App Group・端末内のみ）。
enum AlarmUIDStore {
    private static let uidKey = "alarm_uid_map"
    private static let createdKey = "alarm_created_at_map"

    static func uid(for alarmID: UUID, now: Date = Date()) -> String {
        let key = alarmID.uuidString
        var map = AppGroup.userDefaults.dictionary(forKey: uidKey) as? [String: String] ?? [:]
        if let existing = map[key] { return existing }
        let uid = UUID().uuidString
        map[key] = uid
        AppGroup.userDefaults.set(map, forKey: uidKey)
        recordCreation(alarmID, at: now)
        return uid
    }

    static func recordCreation(_ alarmID: UUID, at date: Date = Date()) {
        let key = alarmID.uuidString
        var map = AppGroup.userDefaults.dictionary(forKey: createdKey) as? [String: Double] ?? [:]
        if map[key] == nil {
            map[key] = date.timeIntervalSince1970
            AppGroup.userDefaults.set(map, forKey: createdKey)
        }
    }

    static func creationDate(for alarmID: UUID, now: Date = Date()) -> Date {
        let key = alarmID.uuidString
        let map = AppGroup.userDefaults.dictionary(forKey: createdKey) as? [String: Double] ?? [:]
        if let seconds = map[key] { return Date(timeIntervalSince1970: seconds) }
        recordCreation(alarmID, at: now)
        return now
    }
}

/// 端末内だけに残すアラーム履歴（JSON Lines・最大5,000行）。
enum AlarmLocalHistoryStore {
    static let maxLines = 5_000
    /// これを超えたら、新しい maxLines 行だけ残して書き直す（毎回全行を読み書きしない）
    static let trimThresholdBytes = 2_500_000
    private static let fileName = "alarm_history.jsonl"
    private static let lock = NSLock()

    static var fileURL: URL {
        AppGroup.containerURL.appendingPathComponent(fileName)
    }

    static func append(
        event: String,
        properties: [String: Any],
        now: Date = Date(),
        fileURL: URL? = nil,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current,
        trimThresholdBytes: Int = AlarmLocalHistoryStore.trimThresholdBytes
    ) {
        var props = properties
        // 端末内は丸めず分単位（#241）
        props["local_time"] = AlarmHistoryLogic.localTimeString(
            now,
            roundingToFiveMinutes: false,
            calendar: calendar,
            timeZone: timeZone
        )
        guard JSONSerialization.isValidJSONObject(props),
              let data = try? JSONSerialization.data(withJSONObject: props, options: [.sortedKeys]),
              let propsJSON = String(data: data, encoding: .utf8)
        else { return }
        // 時系列として使えるよう、日付まで入った時刻（現地のオフセット付き）を必ず残す
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        let ts = formatter.string(from: now)
        let line = #"{"event":"\#(event)","ts":"\#(ts)","properties":\#(propsJSON)}"# + "\n"
        guard let lineData = line.data(using: .utf8) else { return }

        let url = fileURL ?? Self.fileURL
        lock.lock()
        defer { lock.unlock() }

        // 追記だけで済ませる
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: lineData)
        } else {
            try? lineData.write(to: url, options: .atomic)
        }

        // 大きくなったときだけ、古い行を落とす
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard size > trimThresholdBytes,
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
