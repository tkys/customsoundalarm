import Foundation

/// 同期を走らせたきっかけ（#163）。デバッグのリングバッファと計測に使う。
enum AlarmSyncTrigger: String, Codable, Sendable, CaseIterable, Equatable {
    case launch
    case foreground
    case edit
    case playlist
    case intent
    case deferredRetry = "deferred_retry"

    var analyticsValue: String { rawValue }
}

/// アラームを作り直した理由（#163）。
enum AlarmSyncRescheduleReason: String, Codable, Sendable, CaseIterable, Equatable {
    /// 登録内容（署名）が変わった
    case changed
    /// AlarmKit に登録が無い
    case missing
    /// プレイリスト編集などで強制的に作り直す
    case forced
}

/// 通常アラームの登録内容の署名（#163）。
///
/// 同じ署名の `.scheduled` アラームは同期で作り直さない。
/// `soundFileName` は書き出し後のファイル名（プレイリスト・フェードを含む）。
struct AlarmScheduleSignature: Codable, Equatable, Sendable {
    let hour: Int
    let minute: Int
    let repeatWeekdays: [Int]
    let label: String
    let snoozeMinutes: Int
    let soundFileName: String
    let displayName: String
    let fadeIn: Int
    let playlistID: UUID?

    init(
        entry: AlarmEntry,
        soundFileName: String,
        displayName: String
    ) {
        self.hour = entry.hour
        self.minute = entry.minute
        self.repeatWeekdays = entry.repeatWeekdays.sorted()
        self.label = entry.label
        self.snoozeMinutes = entry.snoozeMinutes
        self.soundFileName = soundFileName
        self.displayName = displayName
        self.fadeIn = entry.fadeIn.rawValue
        self.playlistID = entry.playlistID
    }
}

/// 最終アラーム（寝過ごし防止）の登録内容の署名（#163）。
///
/// `fireDate` は `.fixed(date)` の登録時刻。同期のたびに同じ日時が
/// 計算できるので、変更が無ければ作り直さない。
struct BackupAlarmScheduleSignature: Codable, Equatable, Sendable {
    let fireDate: TimeInterval
    let label: String
    let soundFileName: String

    init(entry: AlarmEntry, fireDate: Date, soundFileName: String) {
        self.fireDate = fireDate.timeIntervalSince1970.rounded()
        self.label = entry.label
        self.soundFileName = soundFileName
    }
}

/// 同期の実行記録（#163）。App Group に最新50件を残す。
struct AlarmSyncLogEntry: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let trigger: AlarmSyncTrigger
    let timestamp: Date
    let rescheduledCount: Int
    let deferredCount: Int
    let changedCount: Int
    let missingCount: Int
    let forcedCount: Int

    init(
        id: UUID = UUID(),
        trigger: AlarmSyncTrigger,
        timestamp: Date,
        rescheduledCount: Int,
        deferredCount: Int,
        changedCount: Int,
        missingCount: Int,
        forcedCount: Int
    ) {
        self.id = id
        self.trigger = trigger
        self.timestamp = timestamp
        self.rescheduledCount = rescheduledCount
        self.deferredCount = deferredCount
        self.changedCount = changedCount
        self.missingCount = missingCount
        self.forcedCount = forcedCount
    }
}

/// リングバッファの純ロジック（#163）。
enum AlarmSyncLog {
    static let maxEntries = 50

    /// 追記して最新 `maxEntries` 件だけ返す。
    static func appending(
        _ entry: AlarmSyncLogEntry,
        to log: [AlarmSyncLogEntry]
    ) -> [AlarmSyncLogEntry] {
        var result = log
        result.append(entry)
        if result.count > maxEntries {
            result.removeFirst(result.count - maxEntries)
        }
        return result
    }
}
