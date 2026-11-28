import Foundation

/// プレイリストを作ったあとに「使うアラームを選ぶ」を出した理由（#324）。
enum PlaylistApplySource: String, Sendable, CaseIterable {
    case unlock
    case suggestion
}

/// 「使うアラームを選ぶ」で選んだ行動（#324）。
enum PlaylistApplyAction: String, Sendable, CaseIterable {
    case apply
    case later
    case dismissed
}

/// アラームの本数の区分（#324）。
enum PlaylistApplyAlarmCountBucket: String, Sendable, CaseIterable {
    case zero = "0"
    case one = "1"
    case twoToThree = "2-3"
    case fourToNine = "4-9"
    case tenPlus = "10+"

    init(count: Int) {
        switch count {
        case ..<1: self = .zero
        case 1: self = .one
        case 2...3: self = .twoToThree
        case 4...9: self = .fourToNine
        default: self = .tenPlus
        }
    }
}

/// 作ったプレイリストを、選んだアラームにだけ使う（#324）。
enum PlaylistApplyLogic {
    /// アラームが0本なら、シートではなく追加画面を開く。
    static func shouldOpenAddAlarm(alarmCount: Int) -> Bool {
        alarmCount == 0
    }

    /// 選んだアラームだけプレイリストに差し替える。
    /// 音はプレイリストが持つので、`soundFileName` は空にする。
    static func appliedAlarms(
        _ alarms: [AlarmEntry],
        selectedIDs: Set<UUID>,
        playlistID: UUID
    ) -> [AlarmEntry] {
        alarms.map { alarm in
            guard selectedIDs.contains(alarm.id) else { return alarm }
            var updated = alarm
            updated.playlistID = playlistID
            updated.soundFileName = AlarmDraftLogic.soundFileName(
                playlistID: playlistID,
                selectedSoundFileName: alarm.soundFileName
            )
            return updated
        }
    }
}
