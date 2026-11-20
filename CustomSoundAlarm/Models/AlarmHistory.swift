import Foundation
import AlarmKit

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

    /// 診断ファイル用に、新しい方から最大 `limit` 行を返す（#255）。
    static func recentLines(limit: Int = 200, fileURL: URL? = nil) -> [String] {
        let url = fileURL ?? Self.fileURL
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(max(0, limit))
            .map(String.init)
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

// MARK: - 発火の重複防止と「止めた＝鳴った」の補完（#263）

/// AlarmKit のスケジュールから、いま鳴っている回の発火予定時刻を求める。
enum AlarmFireOccurrence {
    /// - `.fixed`: その日時。
    /// - `.relative(.never)`: 直近の時刻（今日まだなら昨日）。
    /// - `.relative(.weekly)`: 曜日が合う直近の時刻。スヌーズ後の再停止でも同じ値になる。
    static func date(
        for schedule: Alarm.Schedule?,
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard let schedule else { return nil }
        switch schedule {
        case .fixed(let date):
            return date
        case .relative(let relative):
            let hour = relative.time.hour
            let minute = relative.time.minute
            switch relative.repeats {
            case .never:
                return mostRecent(hour: hour, minute: minute, now: now, calendar: calendar)
            case .weekly(let weekdays):
                let allowed = Set(weekdays.map(weekdayNumber))
                for offset in 0...7 {
                    guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else {
                        continue
                    }
                    guard allowed.contains(calendar.component(.weekday, from: day)) else {
                        continue
                    }
                    if let candidate = calendar.date(
                        bySettingHour: hour,
                        minute: minute,
                        second: 0,
                        of: day
                    ), candidate <= now {
                        return candidate
                    }
                }
                return nil
            @unknown default:
                return nil
            }
        @unknown default:
            return nil
        }
    }

    private static func mostRecent(
        hour: Int,
        minute: Int,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        if let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now),
           today <= now {
            return today
        }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else {
            return nil
        }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: yesterday)
    }

    private static func weekdayNumber(_ weekday: Locale.Weekday) -> Int {
        switch weekday {
        case .sunday: 1
        case .monday: 2
        case .tuesday: 3
        case .wednesday: 4
        case .thursday: 5
        case .friday: 6
        case .saturday: 7
        @unknown default: 0
        }
    }
}

/// 「このアラームのこの回はもう alarm_fired を送った」を App Group に残す（#263）。
/// 分単位に丸めた発生時刻と alarm_uid の組で1回だけ。
/// observer（起動中）・reconcile（起動時）・stopped（Intent）をまたいで重複を防ぐ。
enum AlarmFireTracker {
    private static let storageKey = "reported_alarm_fire_occurrences"
    private static let maxCount = 300

    static func hasReported(
        alarmUID: String,
        occurrence: Date,
        defaults: UserDefaults = AppGroup.userDefaults
    ) -> Bool {
        read(defaults).contains(key(alarmUID: alarmUID, occurrence: occurrence))
    }

    /// まだ送っていなければ記録して true。既に送っていれば false。
    @discardableResult
    static func markIfNeeded(
        alarmUID: String,
        occurrence: Date,
        defaults: UserDefaults = AppGroup.userDefaults
    ) -> Bool {
        let key = key(alarmUID: alarmUID, occurrence: occurrence)
        var keys = read(defaults)
        guard !keys.contains(key) else { return false }
        keys.append(key)
        if keys.count > maxCount {
            keys = Array(keys.suffix(maxCount))
        }
        defaults.set(keys, forKey: storageKey)
        return true
    }

    private static func key(alarmUID: String, occurrence: Date) -> String {
        let rounded = (occurrence.timeIntervalSince1970 / 60).rounded(.down) * 60
        return "\(alarmUID)|\(Int(rounded))"
    }

    private static func read(_ defaults: UserDefaults) -> [String] {
        defaults.stringArray(forKey: storageKey) ?? []
    }
}

/// 停止 Intent から「鳴った」を補うイベントを作る（#263）。
enum AlarmFiredBackfill {
    static func event(
        entry: AlarmEntry,
        soundMode: PlaylistSoundMode,
        context: AlarmEventContext
    ) -> AnalyticsEvent {
        .alarmFired(
            wasAppForeground: false,
            hour: entry.hour,
            isRepeating: !entry.repeatWeekdays.isEmpty,
            detection: "stopped",
            soundMode: soundMode,
            context: context
        )
    }

    static func pendingEvent(
        entry: AlarmEntry,
        stoppedAt: Date,
        soundMode: PlaylistSoundMode,
        context: AlarmEventContext
    ) -> PendingAlarmEvent {
        PendingAlarmEvent(
            event: event(entry: entry, soundMode: soundMode, context: context),
            timestamp: stoppedAt
        )
    }
}
