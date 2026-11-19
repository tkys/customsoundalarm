import Foundation

/// 初めての1回きりアラームが鳴って止まったあとの提案（#247）。
enum FirstAlarmFollowupAction: String, Equatable, Sendable, CaseIterable {
    case tomorrow
    case weekdays
    case everyday
    case ignored
}

/// 既存の `alarm_history.jsonl` から、最初に「鳴って止まった」1回きりのアラームを探す。
///
/// 新しい記録は作らず、`alarm_fired` / `alarm_stopped` と `alarm_uid` を使う。
enum FirstAlarmFollowupLogic {

    /// 提案を出してよいアラームの ID。無ければ nil。
    static func candidateAlarmID(
        historyLines: [String],
        alarms: [AlarmEntry],
        uidForAlarm: (UUID) -> String
    ) -> UUID? {
        var uidToAlarmID: [String: UUID] = [:]
        for alarm in alarms {
            uidToAlarmID[uidForAlarm(alarm.id)] = alarm.id
        }

        var firedOneTime: Set<String> = []
        for line in historyLines {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let event = object["event"] as? String,
                  let properties = object["properties"] as? [String: Any],
                  let uid = properties["alarm_uid"] as? String
            else { continue }

            switch event {
            case "alarm_fired":
                let repeatDays = properties["repeat_days"] as? String ?? ""
                let isRepeating = properties["is_repeating"] as? Bool
                    ?? !repeatDays.isEmpty
                if !isRepeating, repeatDays.isEmpty {
                    firedOneTime.insert(uid)
                }
            case "alarm_stopped":
                if firedOneTime.contains(uid), let alarmID = uidToAlarmID[uid] {
                    return alarmID
                }
            default:
                break
            }
        }
        return nil
    }

    /// 1回の起動で出す提案は1つだけ。許可の行 → プレイリストの解放 → この提案の順。
    static func shouldShow(
        hasPermissionBanner: Bool,
        unlockWouldShow: Bool
    ) -> Bool {
        !hasPermissionBanner && !unlockWouldShow
    }

    /// 提案を押したあとのアラーム。押すまで何も変えないので、ここでは値を作るだけ。
    static func updatedAlarm(
        _ alarm: AlarmEntry,
        for action: FirstAlarmFollowupAction
    ) -> AlarmEntry? {
        guard action != .ignored else { return nil }
        var updated = alarm
        switch action {
        case .tomorrow:
            updated.repeatWeekdays = []
        case .weekdays:
            updated.repeatWeekdays = [2, 3, 4, 5, 6]
        case .everyday:
            updated.repeatWeekdays = [1, 2, 3, 4, 5, 6, 7]
        case .ignored:
            return nil
        }
        updated.isEnabled = true
        return updated
    }
}
