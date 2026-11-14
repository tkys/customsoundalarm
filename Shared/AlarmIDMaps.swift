import Foundation

/// 本体アラームと最終アラームの AlarmKit ID マッピング（#110）。
/// App Group に永続化し、停止 Intent（別プロセスでも動く）からも読めるようにする。
enum AlarmIDMaps {
    static let primaryKey = "alarm_id_map"
    static let backupKey = "backup_alarm_id_map"
    /// 休みでくり返しから外した曜日を補う `.fixed` の対応表（#197）。
    /// entryID → [AlarmKit ID: 休みの日キー（yyyy-MM-dd）]
    static let skipCoverageKey = "skip_alarm_id_map"

    static func loadPrimary(defaults: UserDefaults = AppGroup.userDefaults) -> [UUID: UUID] {
        decode(key: primaryKey, defaults: defaults) ?? [:]
    }

    static func loadBackup(defaults: UserDefaults = AppGroup.userDefaults) -> [UUID: UUID] {
        decode(key: backupKey, defaults: defaults) ?? [:]
    }

    static func savePrimary(_ map: [UUID: UUID], defaults: UserDefaults = AppGroup.userDefaults) {
        encode(map, key: primaryKey, defaults: defaults)
    }

    static func saveBackup(_ map: [UUID: UUID], defaults: UserDefaults = AppGroup.userDefaults) {
        encode(map, key: backupKey, defaults: defaults)
    }

    static func loadSkipCoverage(
        defaults: UserDefaults = AppGroup.userDefaults
    ) -> [UUID: [UUID: String]] {
        decode(key: skipCoverageKey, defaults: defaults) ?? [:]
    }

    static func saveSkipCoverage(
        _ map: [UUID: [UUID: String]],
        defaults: UserDefaults = AppGroup.userDefaults
    ) {
        encode(map, key: skipCoverageKey, defaults: defaults)
    }

    /// 休みの補完として登録したアラームなら、その AlarmEntry.ID を返す（#197）。
    static func skipCoverageEntryID(
        of alarmID: UUID,
        map: [UUID: [UUID: String]]
    ) -> UUID? {
        map.first { $0.value.keys.contains(alarmID) }?.key
    }

    /// 停止されたアラームに対応する「もう片方」の ID を返す。
    /// - 本体が停止された → そのアラームの最終アラーム
    /// - 最終アラームが停止された → そのアラームの本体
    static func counterpart(
        of alarmID: UUID,
        primary: [UUID: UUID],
        backup: [UUID: UUID],
        coverage: [UUID: [UUID: String]] = [:]
    ) -> UUID? {
        stopAction(of: alarmID, primary: primary, backup: backup, coverage: coverage)
            .counterpartAlarmID
    }

    /// 停止されたアラームが本体か最終アラームか、休みの補完か。
    enum Role: Equatable, Sendable {
        case primary(entryID: UUID)
        case backup(entryID: UUID)
        /// 休みで外した曜日を補う `.fixed`（#197）
        case coverage(entryID: UUID)
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
        backup: [UUID: UUID],
        coverage: [UUID: [UUID: String]] = [:]
    ) -> StopAction {
        switch role(of: alarmID, primary: primary, backup: backup, coverage: coverage) {
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
        case .coverage(let entryID):
            // 補完の回も「本体の1回」として扱う。その回の最終アラームを取り消す（#197 レビュー）。
            return StopAction(
                role: .coverage(entryID: entryID),
                entryID: entryID,
                counterpartAlarmID: backup[entryID]
            )
        case .unknown:
            return StopAction(role: .unknown, entryID: nil, counterpartAlarmID: nil)
        }
    }

    static func role(
        of alarmID: UUID,
        primary: [UUID: UUID],
        backup: [UUID: UUID],
        coverage: [UUID: [UUID: String]] = [:]
    ) -> Role {
        if let entryID = primary.first(where: { $0.value == alarmID })?.key {
            return .primary(entryID: entryID)
        }
        if let entryID = backup.first(where: { $0.value == alarmID })?.key {
            return .backup(entryID: entryID)
        }
        if let entryID = skipCoverageEntryID(of: alarmID, map: coverage) {
            return .coverage(entryID: entryID)
        }
        return .unknown
    }

    private static func decode<T: Decodable>(
        key: String,
        defaults: UserDefaults
    ) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func encode<T: Encodable>(
        _ map: T,
        key: String,
        defaults: UserDefaults
    ) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: key)
    }
}
