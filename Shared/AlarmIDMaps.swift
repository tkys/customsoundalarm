import Foundation

/// 本体アラームと最終アラームの AlarmKit ID マッピング（#110）。
/// App Group に永続化し、停止 Intent（別プロセスでも動く）からも読めるようにする。
enum AlarmIDMaps {
    static let primaryKey = "alarm_id_map"
    static let backupKey = "backup_alarm_id_map"

    static func loadPrimary(defaults: UserDefaults = AppGroup.userDefaults) -> [UUID: UUID] {
        decode(key: primaryKey, defaults: defaults)
    }

    static func loadBackup(defaults: UserDefaults = AppGroup.userDefaults) -> [UUID: UUID] {
        decode(key: backupKey, defaults: defaults)
    }

    static func savePrimary(_ map: [UUID: UUID], defaults: UserDefaults = AppGroup.userDefaults) {
        encode(map, key: primaryKey, defaults: defaults)
    }

    static func saveBackup(_ map: [UUID: UUID], defaults: UserDefaults = AppGroup.userDefaults) {
        encode(map, key: backupKey, defaults: defaults)
    }

    /// 停止されたアラームに対応する「もう片方」の ID を返す。
    /// - 本体が停止された → そのアラームの最終アラーム
    /// - 最終アラームが停止された → そのアラームの本体
    static func counterpart(
        of alarmID: UUID,
        primary: [UUID: UUID],
        backup: [UUID: UUID]
    ) -> UUID? {
        stopAction(of: alarmID, primary: primary, backup: backup).counterpartAlarmID
    }

    /// 停止されたアラームが本体か最終アラームか。
    enum Role: Equatable, Sendable {
        case primary(entryID: UUID)
        case backup(entryID: UUID)
        case unknown
    }

    /// 停止時にやるべきこと（対応表）。
    struct StopAction: Equatable, Sendable {
        let role: Role
        /// 対応する AlarmEntry.ID（unknown は nil）
        let entryID: UUID?
        /// 一緒に取り消す「もう片方」の AlarmKit ID
        let counterpartAlarmID: UUID?
    }

    static func stopAction(
        of alarmID: UUID,
        primary: [UUID: UUID],
        backup: [UUID: UUID]
    ) -> StopAction {
        switch role(of: alarmID, primary: primary, backup: backup) {
        case .primary(let entryID):
            return StopAction(
                role: .primary(entryID: entryID),
                entryID: entryID,
                counterpartAlarmID: backup[entryID]
            )
        case .backup(let entryID):
            return StopAction(
                role: .backup(entryID: entryID),
                entryID: entryID,
                counterpartAlarmID: primary[entryID]
            )
        case .unknown:
            return StopAction(role: .unknown, entryID: nil, counterpartAlarmID: nil)
        }
    }

    static func role(
        of alarmID: UUID,
        primary: [UUID: UUID],
        backup: [UUID: UUID]
    ) -> Role {
        if let entryID = primary.first(where: { $0.value == alarmID })?.key {
            return .primary(entryID: entryID)
        }
        if let entryID = backup.first(where: { $0.value == alarmID })?.key {
            return .backup(entryID: entryID)
        }
        return .unknown
    }

    private static func decode(
        key: String,
        defaults: UserDefaults
    ) -> [UUID: UUID] {
        guard let data = defaults.data(forKey: key),
              let map = try? JSONDecoder().decode([UUID: UUID].self, from: data)
        else { return [:] }
        return map
    }

    private static func encode(
        _ map: [UUID: UUID],
        key: String,
        defaults: UserDefaults
    ) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: key)
    }
}
