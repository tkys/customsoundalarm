import Testing
import Foundation
import AlarmKit
@testable import CustomSoundAlarm

/// 同期の途中打ち切りで「アプリから見えないアラーム」が残る問題の再現（App Store レビュー・1.8.0）。
///
/// `syncAlarms` は新しい同期が始まると前の同期を止める。前の同期が AlarmKit への登録を
/// 済ませた後に止まると、対応表に書かれないまま AlarmKit にだけ残る。
/// 残ったアラームはアプリの一覧に出ず、削除もできず、毎日その時刻に鳴り続ける。
@MainActor
@Suite(.serialized)
struct AlarmSchedulerOrphanTests {

    // MARK: - Helpers

    /// App Group に保存している同期の状態を空にし、終わったら元に戻す。
    private func withCleanSyncState(_ body: () async throws -> Void) async rethrows {
        let primary = AlarmIDMaps.loadPrimary()
        let backup = AlarmIDMaps.loadBackup()
        let primarySignatures = AppGroup.primaryAlarmSignatures
        let backupSignatures = AppGroup.backupAlarmSignatures
        let primaryNames = AppGroup.primarySoundNames
        let syncLog = AppGroup.alarmSyncLog
        let lastStop = AppGroup.lastStopIntentAt
        let testRecords = AppGroup.testAlarmRecords
        defer {
            AppGroup.lastStopIntentAt = lastStop
            AppGroup.testAlarmRecords = testRecords
            AlarmIDMaps.savePrimary(primary)
            AlarmIDMaps.saveBackup(backup)
            AppGroup.primaryAlarmSignatures = primarySignatures
            AppGroup.backupAlarmSignatures = backupSignatures
            AppGroup.primarySoundNames = primaryNames
            AppGroup.alarmSyncLog = syncLog
        }
        AlarmIDMaps.savePrimary([:])
        AlarmIDMaps.saveBackup([:])
        AppGroup.primaryAlarmSignatures = [:]
        AppGroup.backupAlarmSignatures = [:]
        AppGroup.primarySoundNames = [:]
        AppGroup.lastStopIntentAt = nil
        AppGroup.testAlarmRecords = []
        try await body()
    }

    private func entries(count: Int) -> [AlarmEntry] {
        (0..<count).map { index in
            AlarmEntry(
                hour: 0,
                minute: index,
                label: "orphan-test-\(index)",
                repeatWeekdays: Array(1...7),
                soundFileName: "orphan-test.caf"
            )
        }
    }

    // MARK: - Tests

    /// 1回目の同期が登録中に2回目の同期が来ても、AlarmKit に登録された本体アラームは
    /// すべて対応表に載っていること（＝アプリから管理できること）。
    /// 修正前は1回目が打ち切られ、登録済みの1件が対応表に書かれず残った（登録4件・対応表3件）。
    @Test
    func overlappingSyncs_leaveNoUnmappedAlarms() async throws {
        try await withCleanSyncState {
            let fake = GatedAlarmManager()
            let scheduler = AlarmScheduler(manager: fake)
            let alarms = entries(count: 3)

            // 1回目: 最初の登録で止めておく（AlarmKit 側には登録済み）
            scheduler.syncAlarms(alarms, trigger: .launch)
            await fake.waitUntilGated()

            // 2回目: 起動直後の前面復帰と同じく、すぐ次の同期が来る
            scheduler.syncAlarms(alarms, trigger: .foreground)

            fake.releaseGate()
            await scheduler.waitForPendingSync()

            let registered = fake.registeredIDs
            let mapped = Set(scheduler.primaryAlarmIDMap.values)
            let unmapped = registered.subtracting(mapped)

            #expect(unmapped.isEmpty, "AlarmKit にあるのに対応表に無いアラーム: \(unmapped.count)件")
            #expect(registered.count == alarms.count, "登録数 \(registered.count) / アラーム \(alarms.count)")
        }
    }

    /// 同期が重なった後にアプリでアラームを全部削除すると、AlarmKit からも消えること。
    @Test
    func overlappingSyncs_thenDeleteAll_leavesNothing() async throws {
        try await withCleanSyncState {
            let fake = GatedAlarmManager()
            let scheduler = AlarmScheduler(manager: fake)
            let alarms = entries(count: 3)

            scheduler.syncAlarms(alarms, trigger: .launch)
            await fake.waitUntilGated()
            scheduler.syncAlarms(alarms, trigger: .foreground)
            fake.releaseGate()
            await scheduler.waitForPendingSync()

            // ユーザーがアプリ上のアラームを全部削除する
            scheduler.syncAlarms([], trigger: .edit)
            await scheduler.waitForPendingSync()

            #expect(fake.registeredIDs.isEmpty, "全削除後も AlarmKit に残っているアラーム: \(fake.registeredIDs.count)件")
        }
    }

    /// 1.8.0 で既に取り残されたアラームは、起動時の同期で取り消されること。
    @Test
    func launchSync_cancelsPreexistingOrphan() async throws {
        try await withCleanSyncState {
            let fake = GatedAlarmManager(gated: false)
            let orphan = Alarm.ID()
            fake.preload(orphan, state: .scheduled)
            let scheduler = AlarmScheduler(manager: fake)
            let alarms = entries(count: 2)

            scheduler.syncAlarms(alarms, trigger: .launch)
            await scheduler.waitForPendingSync()

            #expect(!fake.registeredIDs.contains(orphan))
            #expect(fake.registeredIDs == Set(scheduler.primaryAlarmIDMap.values))
        }
    }

    /// 停止によるバックグラウンド起動（intent）の同期では掃除しないこと。
    /// Intent が直接登録した寝過ごし防止の次回分を消さないため。
    @Test
    func intentSync_keepsUnknownAlarms() async throws {
        try await withCleanSyncState {
            let fake = GatedAlarmManager(gated: false)
            let unknown = Alarm.ID()
            fake.preload(unknown, state: .scheduled)
            let scheduler = AlarmScheduler(manager: fake)

            scheduler.syncAlarms(entries(count: 1), trigger: .intent)
            await scheduler.waitForPendingSync()

            #expect(fake.registeredIDs.contains(unknown))
        }
    }

    /// 停止 Intent の直後（5分以内）の前面復帰でも掃除しないこと。
    @Test
    func foregroundSyncRightAfterStop_keepsUnknownAlarms() async throws {
        try await withCleanSyncState {
            AppGroup.lastStopIntentAt = Date().addingTimeInterval(-60)
            let fake = GatedAlarmManager(gated: false)
            let unknown = Alarm.ID()
            fake.preload(unknown, state: .scheduled)
            let scheduler = AlarmScheduler(manager: fake)

            scheduler.syncAlarms(entries(count: 1), trigger: .foreground)
            await scheduler.waitForPendingSync()

            #expect(fake.registeredIDs.contains(unknown))
        }
    }

    /// 鳴動中・スヌーズ中のアラームは、対応表に無くても掃除しないこと。
    @Test
    func launchSync_keepsRingingAndSnoozedUnknownAlarms() async throws {
        try await withCleanSyncState {
            let fake = GatedAlarmManager(gated: false)
            let ringing = Alarm.ID()
            let snoozed = Alarm.ID()
            fake.preload(ringing, state: .alerting)
            fake.preload(snoozed, state: .countdown)
            let scheduler = AlarmScheduler(manager: fake)

            scheduler.syncAlarms([], trigger: .launch)
            await scheduler.waitForPendingSync()

            #expect(fake.registeredIDs.contains(ringing))
            #expect(fake.registeredIDs.contains(snoozed))
        }
    }

    /// 試し鳴らしの記録にあるアラームは掃除しないこと。
    @Test
    func launchSync_keepsTestRing() async throws {
        try await withCleanSyncState {
            let fake = GatedAlarmManager(gated: false)
            let testRing = Alarm.ID()
            fake.preload(testRing, state: .scheduled)
            AppGroup.testAlarmRecords = [TestAlarmRecord(id: testRing, scheduledAt: Date(), kind: .own)]
            let scheduler = AlarmScheduler(manager: fake)

            scheduler.syncAlarms([], trigger: .launch)
            await scheduler.waitForPendingSync()

            #expect(fake.registeredIDs.contains(testRing))
        }
    }
}

// MARK: - Fake

/// 最初の `schedule` だけ、登録を済ませた状態で止める偽の AlarmKit。
/// 実機の「登録は終わったが、呼び出し元に戻る前に次の同期が来た」を作る。
final class GatedAlarmManager: AlarmManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var registered: [Alarm.ID: Alarm.State] = [:]
    private var gateArmed: Bool
    private var gated = false
    private var gateContinuation: CheckedContinuation<Void, Never>?
    private var gatedWaiter: CheckedContinuation<Void, Never>?

    init(gated: Bool = true) {
        gateArmed = gated
    }

    /// 以前から AlarmKit に残っているアラームを置く
    func preload(_ id: Alarm.ID, state: Alarm.State) {
        lock.withLock { registered[id] = state }
    }

    var registeredIDs: Set<Alarm.ID> {
        lock.withLock { Set(registered.keys) }
    }

    var authorizationState: AlarmManager.AuthorizationState { .authorized }

    func requestAuthorization() async throws -> AlarmManager.AuthorizationState {
        .authorized
    }

    func alarmSnapshots() throws -> [AlarmSnapshot] {
        lock.withLock { registered.map { AlarmSnapshot(id: $0.key, state: $0.value) } }
    }

    func schedule(
        id: Alarm.ID,
        configuration: AlarmManager.AlarmConfiguration<CustomAlarmMetadata>
    ) async throws {
        let shouldGate = lock.withLock { () -> Bool in
            registered[id] = .scheduled
            guard gateArmed else { return false }
            gateArmed = false
            return true
        }
        guard shouldGate else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let waiter = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                gateContinuation = continuation
                gated = true
                let waiter = gatedWaiter
                gatedWaiter = nil
                return waiter
            }
            waiter?.resume()
        }
    }

    func cancel(id: Alarm.ID) throws {
        lock.withLock { _ = registered.removeValue(forKey: id) }
    }

    /// 最初の登録で止まるまで待つ
    func waitUntilGated() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alreadyGated = lock.withLock { () -> Bool in
                if gated { return true }
                gatedWaiter = continuation
                return false
            }
            if alreadyGated { continuation.resume() }
        }
    }

    /// 止めていた登録を再開する
    func releaseGate() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            let continuation = gateContinuation
            gateContinuation = nil
            return continuation
        }
        continuation?.resume()
    }
}
