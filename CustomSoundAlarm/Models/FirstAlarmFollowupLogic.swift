import Foundation

/// 初めての1回きりアラームが鳴って止まったあとの提案（#247）。
enum FirstAlarmFollowupAction: String, Equatable, Sendable, CaseIterable {
    case tomorrow
    case weekdays
    case everyday
    case ignored
}

/// 履歴から見つけた候補。アラームが消えている場合は `alarmID` が nil。
struct FirstAlarmFollowupCandidate: Equatable, Sendable {
    let alarmID: UUID?
    let stoppedAt: Date?
}

enum FirstAlarmFollowupEligibility: Equatable, Sendable {
    case offer(UUID)
    /// オンにされた・繰り返しに変えられた・削除された
    case changedOrRemoved
    /// 止めてから3日を超えた
    case tooOld
    /// 候補なし（履歴の最初が繰り返し、まだ止まっていない等）
    case none
}

/// 既存の `alarm_history.jsonl` から、最初に「鳴って止まった」1回きりのアラームを探す。
///
/// 新しい記録は作らず、`alarm_fired` / `alarm_stopped` と `alarm_uid` を使う。
enum FirstAlarmFollowupLogic {

    /// 履歴が揃っている最初のバージョン。これより前にインストールした人は対象外。
    static let minimumFirstInstallVersion = "1.8.3"

    /// 止めてから提案を出せる日数。
    static let maximumDaysSinceStopped: Double = 3

    /// 履歴の中で最初の `alarm_fired` が1回きりで、その `alarm_stopped` まで揃っているもの。
    static func candidate(
        historyLines: [String],
        alarms: [AlarmEntry],
        uidForAlarm: (UUID) -> String
    ) -> FirstAlarmFollowupCandidate? {
        var uidToAlarmID: [String: UUID] = [:]
        for alarm in alarms {
            uidToAlarmID[uidForAlarm(alarm.id)] = alarm.id
        }

        var firstFiredUID: String?
        for line in historyLines {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let event = object["event"] as? String,
                  let properties = object["properties"] as? [String: Any],
                  let uid = properties["alarm_uid"] as? String
            else { continue }

            if firstFiredUID == nil {
                guard event == "alarm_fired" else { continue }
                let repeatDays = properties["repeat_days"] as? String ?? ""
                let isRepeating = properties["is_repeating"] as? Bool
                    ?? !repeatDays.isEmpty
                // 最初に鳴ったのが繰り返しなら、その人は対象外（#247 レビュー）
                guard !isRepeating, repeatDays.isEmpty else { return nil }
                firstFiredUID = uid
                continue
            }

            if event == "alarm_stopped", uid == firstFiredUID {
                return FirstAlarmFollowupCandidate(
                    alarmID: uidToAlarmID[uid],
                    stoppedAt: parseTimestamp(object["ts"] as? String)
                )
            }
        }
        return nil
    }

    /// 初回インストール版が 1.8.3 以上か（数値の版数として比較）。
    static func isFirstInstallVersionEligible(_ version: String?) -> Bool {
        guard let version else { return false }
        return compareVersions(version, minimumFirstInstallVersion) >= 0
    }

    /// 候補をいま出してよいか。出す条件は「今もオフの1回きり」「止めてから3日以内」。
    static func eligibility(
        candidate: FirstAlarmFollowupCandidate?,
        alarms: [AlarmEntry],
        now: Date = Date()
    ) -> FirstAlarmFollowupEligibility {
        guard let candidate else { return .none }
        guard let alarmID = candidate.alarmID,
              let alarm = alarms.first(where: { $0.id == alarmID })
        else { return .changedOrRemoved }
        guard !alarm.isEnabled, alarm.repeatWeekdays.isEmpty else {
            return .changedOrRemoved
        }
        guard let stoppedAt = candidate.stoppedAt,
              now.timeIntervalSince(stoppedAt) <= maximumDaysSinceStopped * 86_400
        else { return .tooOld }
        return .offer(alarmID)
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

    // MARK: - Helpers

    private static func parseTimestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> Int {
        let left = versionComponents(lhs)
        let right = versionComponents(rhs)
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l < r ? -1 : 1 }
        }
        return 0
    }

    private static func versionComponents(_ version: String) -> [Int] {
        version.split(separator: ".").map { component in
            Int(component.prefix(while: \.isNumber)) ?? 0
        }
    }
}
