import Foundation

/// 起動時同期のきっかけ判定（#163）。
enum AlarmSyncTriggerLogic {
    /// 直近に停止 Intent が動いていれば、バックグラウンド起動とみなして `intent` にする。
    static func launchTrigger(
        now: Date,
        lastStopIntentAt: Date?,
        window: TimeInterval = 30
    ) -> AlarmSyncTrigger {
        guard let lastStopIntentAt else { return .launch }
        let elapsed = now.timeIntervalSince(lastStopIntentAt)
        return (elapsed >= 0 && elapsed < window) ? .intent : .launch
    }
}

/// 発火した分の中で繰り返しアラームを作り直さないための安全柵（#163）。
enum AlarmSyncSafety {
    /// 作り直しを次の同期まで延期すべきか。
    ///
    /// 繰り返しアラームの時刻が「今の分」または「直前の分」に当たる間は、
    /// AlarmKit の登録を作り直すとその分が次の発火と解釈されて即座に鳴り直す
    /// ことがあるため延期する。
    ///
    /// - Parameter editedEntryIDs: ユーザーがその場で保存したアラーム。
    ///   時刻編集を即座に反映するため延期しない。
    static func shouldDeferReschedule(
        for entry: AlarmEntry,
        editedEntryIDs: Set<UUID> = [],
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard !editedEntryIDs.contains(entry.id) else { return false }
        guard entry.isEnabled, !entry.repeatWeekdays.isEmpty else { return false }
        guard let currentMinute = calendar.dateInterval(of: .minute, for: now)?.start,
              let previousMinute = calendar.date(
                  byAdding: .minute,
                  value: -1,
                  to: currentMinute
              )
        else { return false }

        // 日付をまたぐ「直前の分」も拾うため、今日と昨日の時刻を比べる。
        let bases = [now, calendar.date(byAdding: .day, value: -1, to: now) ?? now]
        for base in bases {
            guard let fire = calendar.date(
                bySettingHour: entry.hour,
                minute: entry.minute,
                second: 0,
                of: base
            ) else { continue }
            guard entry.repeatWeekdays.contains(
                calendar.component(.weekday, from: fire)
            ) else { continue }
            let fireMinute = calendar.dateInterval(of: .minute, for: fire)?.start
            if fireMinute == currentMinute || fireMinute == previousMinute {
                return true
            }
        }
        return false
    }
}
