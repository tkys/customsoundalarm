import Foundation

/// AppIntent（killed状態で実行される）からアナリティクスイベントを
/// App Group UserDefaults 経由でバッファリングするためのモデル。
/// AnalyticsService が次回起動時にフラッシュする。
///
/// properties は PostHog の `[String: Any]` に変換可能な値のみ保持する。
/// Intent 実行時は PostHog SDK が未初期化の可能性が高いため、直接送信せずバッファする。
struct PendingAlarmEvent: Codable, Sendable {
    var name: String
    /// String / Int / Bool のみ（JSON で安全にシリアライズできる値）
    var properties: [String: String]
    /// PII 安全な時刻情報（アラーム発火想定時刻等）。デバッグ/分析以外の用途には使わない
    var timestamp: Date
}

/// App Group UserDefaults をバッファにしたアラームイベントキュー。
enum AlarmEventBuffer {
    private static let key = "pending_alarm_events"
    /// 上限件数。超えた場合は古いものから削除する。PostHog 未設定環境で無制限に増えるのを防ぐ。
    private static let maxCount = 100

    /// イベントをキューに追加する（Intent 実行時など、PostHog SDK が使えない文脈で呼ぶ）
    static func enqueue(_ event: PendingAlarmEvent, defaults: UserDefaults = AppGroup.userDefaults) {
        var queue = readAll(defaults: defaults)
        queue.append(event)
        if queue.count > maxCount {
            queue = Array(queue.suffix(maxCount))
        }
        guard let data = try? JSONEncoder().encode(queue) else { return }
        defaults.set(data, forKey: key)
    }

    /// 全イベントを読み取り、キューをクリアする（AnalyticsService 初期化後に呼ぶ）
    static func dequeueAll(defaults: UserDefaults = AppGroup.userDefaults) -> [PendingAlarmEvent] {
        let events = readAll(defaults: defaults)
        defaults.removeObject(forKey: key)
        return events
    }

    private static func readAll(defaults: UserDefaults = AppGroup.userDefaults) -> [PendingAlarmEvent] {
        guard let data = defaults.data(forKey: key),
              let events = try? JSONDecoder().decode([PendingAlarmEvent].self, from: data)
        else { return [] }
        return events
    }
}
