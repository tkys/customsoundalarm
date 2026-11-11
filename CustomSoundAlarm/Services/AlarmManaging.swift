import Foundation
import AlarmKit

/// AlarmKit の登録・取消・一覧を差し替えられるようにする口。
///
/// 本番は `SystemAlarmManager`（`AlarmManager.shared` をそのまま呼ぶ）。
/// テストでは偽物を渡して、同期の途中打ち切りなど実機で起こしにくい順序を再現する。
/// 状態の監視（`alarmUpdates`）は対象外で、`AlarmScheduler` が直接 `AlarmManager` を使う。
protocol AlarmManaging: AnyObject, Sendable {
    var authorizationState: AlarmManager.AuthorizationState { get }
    func requestAuthorization() async throws -> AlarmManager.AuthorizationState
    /// 登録中のアラームの ID と状態
    func alarmSnapshots() throws -> [AlarmSnapshot]
    func schedule(
        id: Alarm.ID,
        configuration: AlarmManager.AlarmConfiguration<CustomAlarmMetadata>
    ) async throws
    func cancel(id: Alarm.ID) throws
}

/// 登録中のアラームのうち、同期と整合性チェックに使う部分だけを持つ。
struct AlarmSnapshot: Equatable, Sendable {
    let id: Alarm.ID
    let state: Alarm.State
}

/// 本番用: `AlarmManager.shared` に委ねる。
final class SystemAlarmManager: AlarmManaging, @unchecked Sendable {
    private let manager = AlarmManager.shared

    var authorizationState: AlarmManager.AuthorizationState {
        manager.authorizationState
    }

    func requestAuthorization() async throws -> AlarmManager.AuthorizationState {
        try await manager.requestAuthorization()
    }

    func alarmSnapshots() throws -> [AlarmSnapshot] {
        try manager.alarms.map { AlarmSnapshot(id: $0.id, state: $0.state) }
    }

    func schedule(
        id: Alarm.ID,
        configuration: AlarmManager.AlarmConfiguration<CustomAlarmMetadata>
    ) async throws {
        _ = try await manager.schedule(id: id, configuration: configuration)
    }

    func cancel(id: Alarm.ID) throws {
        try manager.cancel(id: id)
    }
}
