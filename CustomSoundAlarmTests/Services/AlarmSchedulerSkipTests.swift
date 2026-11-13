import Testing
import Foundation
import AlarmKit
@testable import CustomSoundAlarm

/// 休みでくり返しから外した曜日と補完の登録（#197）。
///
/// 偽の `AlarmManaging` で、AlarmKit に何が登録・取消されたかを確認する。
@MainActor
@Suite(.serialized)
struct AlarmSchedulerSkipTests {

    // MARK: - Helpers

    private func withCleanState(_ body: () async throws -> Void) async rethrows {
        let primary = AlarmIDMaps.loadPrimary()
        let backup = AlarmIDMaps.loadBackup()
        let coverage = AlarmIDMaps.loadSkipCoverage()
        let primarySignatures = AppGroup.primaryAlarmSignatures
        let backupSignatures = AppGroup.backupAlarmSignatures
        let primaryNames = AppGroup.primarySoundNames
        let backupNames = AppGroup.backupSoundNames
        let syncLog = AppGroup.alarmSyncLog
        let lastStop = AppGroup.lastStopIntentAt
        let testRecords = AppGroup.testAlarmRecords
        let pendingShuffle = AppGroup.pendingShuffleRefreshEntryIDs
        let globalSkip = AppGroup.globalSkip
        defer {
            AppGroup.globalSkip = globalSkip
            AppGroup.lastStopIntentAt = lastStop
            AppGroup.testAlarmRecords = testRecords
            AppGroup.pendingShuffleRefreshEntryIDs = pendingShuffle
            AlarmIDMaps.savePrimary(primary)
            AlarmIDMaps.saveBackup(backup)
            AlarmIDMaps.saveSkipCoverage(coverage)
            AppGroup.primaryAlarmSignatures = primarySignatures
            AppGroup.backupAlarmSignatures = backupSignatures
            AppGroup.primarySoundNames = primaryNames
            AppGroup.backupSoundNames = backupNames
            AppGroup.alarmSyncLog = syncLog
        }
        AlarmIDMaps.savePrimary([:])
        AlarmIDMaps.saveBackup([:])
        AlarmIDMaps.saveSkipCoverage([:])
        AppGroup.primaryAlarmSignatures = [:]
        AppGroup.backupAlarmSignatures = [:]
        AppGroup.primarySoundNames = [:]
        AppGroup.backupSoundNames = [:]
        AppGroup.lastStopIntentAt = nil
        AppGroup.testAlarmRecords = []
        AppGroup.pendingShuffleRefreshEntryIDs = []
        AppGroup.globalSkip = nil
        try await body()
    }

    /// `AlarmConfiguration` は schedule を公開していないため、テストからは Mirror で読む。
    private func schedule(of configuration: AlarmManager.AlarmConfiguration<CustomAlarmMetadata>) -> Alarm.Schedule? {
        Mirror(reflecting: configuration).children.compactMap { child in
            child.value as? Alarm.Schedule
        }.first
    }

    private func weekdaySet(_ schedule: Alarm.Schedule) -> Set<Int>? {
        guard case .relative(let relative) = schedule,
              case .weekly(let days) = relative.repeats else {
            return nil
        }
        return Set(days.map { day -> Int in
            switch day {
            case .sunday: 1
            case .monday: 2
            case .tuesday: 3
            case .wednesday: 4
            case .thursday: 5
            case .friday: 6
            case .saturday: 7
            @unknown default: 0
            }
        })
    }

    private func isFixed(_ schedule: Alarm.Schedule) -> Bool {
        if case .fixed = schedule { return true }
        return false
    }

    private var tomorrowKey: String {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        return AlarmSkipLogic.dateKey(tomorrow)
    }

    // MARK: - Tests

    @Test
    func skippedDay_removesWeekdayAndRegistersCoverage() async throws {
        try await withCleanState {
            let fake = RecordingAlarmManager()
            let scheduler = AlarmScheduler(manager: fake)
            let entry = AlarmEntry(
                hour: 7,
                minute: 0,
                label: "skip-test",
                repeatWeekdays: [1, 2, 3, 4, 5, 6, 7],
                skipDates: [tomorrowKey]
            )

            scheduler.syncAlarms([entry], trigger: .launch)
            await scheduler.waitForPendingSync()

            let weekly = fake.configurations.values.compactMap { schedule(of: $0).flatMap(weekdaySet) }
            #expect(weekly.count == 1)
            let tomorrowWeekday = Calendar.current.component(
                .weekday,
                from: Calendar.current.date(byAdding: .day, value: 1, to: Date())!
            )
            #expect(!weekly[0].contains(tomorrowWeekday))
            #expect(weekly[0].count == 6)

            let coverageIDs = Set((AlarmIDMaps.loadSkipCoverage()[entry.id] ?? [:]).keys)
            #expect(!coverageIDs.isEmpty)
            #expect(fake.configurations.values.contains { schedule(of: $0).map(isFixed) ?? false })

            // 登録した ID はすべて対応表にある（取り残しが無い）
            let mapped = Set(scheduler.primaryAlarmIDMap.values).union(coverageIDs)
            #expect(mapped == fake.registeredIDs)
        }
    }

    @Test
    func undo_restoresTheOriginalWeekdaysAndRemovesCoverage() async throws {
        try await withCleanState {
            let fake = RecordingAlarmManager()
            let scheduler = AlarmScheduler(manager: fake)
            let entry = AlarmEntry(
                hour: 7,
                minute: 0,
                label: "skip-test",
                repeatWeekdays: [1, 2, 3, 4, 5, 6, 7],
                skipDates: [tomorrowKey]
            )
            scheduler.syncAlarms([entry], trigger: .launch)
            await scheduler.waitForPendingSync()
            #expect(!(AlarmIDMaps.loadSkipCoverage()[entry.id] ?? [:]).isEmpty)

            var restored = entry
            restored.skipDates = []
            scheduler.syncAlarms([restored], trigger: .edit)
            await scheduler.waitForPendingSync()

            let weekly = fake.configurations.values.compactMap { schedule(of: $0).flatMap(weekdaySet) }
            #expect(weekly.count == 1)
            #expect(weekly[0] == Set([1, 2, 3, 4, 5, 6, 7]))
            #expect((AlarmIDMaps.loadSkipCoverage()[entry.id] ?? [:]).isEmpty)
            #expect(fake.configurations.values.allSatisfy { schedule(of: $0).map(isFixed) == false })
        }
    }

    @Test
    func deletingTheAlarmRemovesEveryAlarmKitRegistration() async throws {
        try await withCleanState {
            let fake = RecordingAlarmManager()
            let scheduler = AlarmScheduler(manager: fake)
            let entry = AlarmEntry(
                hour: 7,
                minute: 0,
                label: "skip-test",
                repeatWeekdays: [1, 2, 3, 4, 5, 6, 7],
                skipDates: [tomorrowKey]
            )
            scheduler.syncAlarms([entry], trigger: .launch)
            await scheduler.waitForPendingSync()
            #expect(!fake.registeredIDs.isEmpty)

            scheduler.syncAlarms([], trigger: .edit)
            await scheduler.waitForPendingSync()

            #expect(fake.registeredIDs.isEmpty)
            #expect(AlarmIDMaps.loadSkipCoverage().isEmpty)
            #expect(scheduler.primaryAlarmIDMap.isEmpty)
        }
    }

    @Test
    func editingAnAlarmLeavesNoUnmappedRegistrations() async throws {
        try await withCleanState {
            let fake = RecordingAlarmManager()
            let scheduler = AlarmScheduler(manager: fake)
            let entry = AlarmEntry(
                hour: 7,
                minute: 0,
                label: "skip-test",
                repeatWeekdays: [1, 2, 3, 4, 5, 6, 7],
                skipDates: [tomorrowKey]
            )
            scheduler.syncAlarms([entry], trigger: .launch)
            await scheduler.waitForPendingSync()

            var edited = entry
            edited.label = "skip-test-edited"
            edited.hour = 8
            scheduler.syncAlarms([edited], trigger: .edit)
            await scheduler.waitForPendingSync()

            let coverageIDs = Set((AlarmIDMaps.loadSkipCoverage()[entry.id] ?? [:]).keys)
            let mapped = Set(scheduler.primaryAlarmIDMap.values).union(coverageIDs)
            #expect(mapped == fake.registeredIDs)
        }
    }

    @Test
    func allWeekdaysSkipped_registersTheWholeHorizon() async throws {
        try await withCleanState {
            let fake = RecordingAlarmManager()
            let scheduler = AlarmScheduler(manager: fake)
            let calendar = Calendar.current
            let keys = (0..<7).compactMap { offset in
                calendar.date(byAdding: .day, value: offset, to: Date())
                    .map { AlarmSkipLogic.dateKey($0) }
            }
            let entry = AlarmEntry(
                hour: 7,
                minute: 0,
                label: "skip-all",
                repeatWeekdays: [1, 2, 3, 4, 5, 6, 7],
                skipDates: keys
            )
            scheduler.syncAlarms([entry], trigger: .launch)
            await scheduler.waitForPendingSync()

            #expect(fake.configurations.values.allSatisfy { schedule(of: $0).map(isFixed) == true })
            // 本体（.fixed）1件 + 休み明けの70日分の補完
            #expect(fake.configurations.count >= 60)
            #expect(scheduler.primaryAlarmIDMap.count == 1)
            let coverageIDs = Set((AlarmIDMaps.loadSkipCoverage()[entry.id] ?? [:]).keys)
            #expect(coverageIDs.count >= 60)
            let mapped = Set(scheduler.primaryAlarmIDMap.values).union(coverageIDs)
            #expect(mapped == fake.registeredIDs)
        }
    }

    @Test
    func disabledOneTimeAlarm_isNotRegistered() async throws {
        try await withCleanState {
            let fake = RecordingAlarmManager()
            let scheduler = AlarmScheduler(manager: fake)
            var entry = AlarmEntry(
                hour: 7,
                minute: 0,
                label: "one-time-off",
                repeatWeekdays: []
            )
            entry.isEnabled = false
            entry.skipDisabledDate = AlarmSkipLogic.dateKey(Date())

            scheduler.syncAlarms([entry], trigger: .launch)
            await scheduler.waitForPendingSync()

            // 休みで止めた1回だけは、翌日になっても登録されない
            #expect(fake.registeredIDs.isEmpty)
        }
    }

    /// AlarmKit の登録上限の確認（レビュー用・シミュレータのみ）。
    /// 認可されていない環境ではスキップする。
    @Test
    func register200FixedAlarmsOnSimulator() async {
        #if targetEnvironment(simulator)
        let manager = AlarmManager.shared
        if manager.authorizationState != .authorized {
            _ = try? await manager.requestAuthorization()
        }
        guard manager.authorizationState == .authorized else {
            let message = "skipped (authorization=\(manager.authorizationState))"
            AppGroup.userDefaults.set(message, forKey: "capacity_test_result")
        AppGroup.userDefaults.synchronize()
            AppGroup.userDefaults.synchronize()
            print("CAPACITY: \(message)")
            return
        }
        let entry = AlarmEntry(hour: 7, minute: 0, label: "capacity")
        let base = Date().addingTimeInterval(60 * 60 * 24 * 30)
        var registered: [Alarm.ID] = []
        var failure: String?
        for index in 0..<200 {
            let id = Alarm.ID()
            let config = BackupAlarmFactory.configuration(
                for: entry,
                fireDate: base.addingTimeInterval(Double(index) * 60),
                alarmID: id,
                displayName: "capacity"
            )
            do {
                _ = try await manager.schedule(id: id, configuration: config)
                registered.append(id)
            } catch {
                failure = "at \(index): \(error)"
                break
            }
        }
        for id in registered {
            try? manager.cancel(id: id)
        }
        print("CAPACITY: registered=\(registered.count) failure=\(failure ?? "none")")
        #expect(failure == nil, "AlarmKit registration failed: \(failure ?? "")")
        #endif
    }

    @Test
    func backupAfterSkip_isNotScheduledOnTheSkippedDay() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let nextWeekday = calendar.date(byAdding: .day, value: 1, to: today)!
        let key = AlarmSkipLogic.dateKey(nextWeekday)
        let weekday = calendar.component(.weekday, from: nextWeekday)
        var entry = AlarmEntry(
            hour: 7,
            minute: 0,
            repeatWeekdays: [weekday],
            backupMinutes: 15,
            skipDates: [key]
        )
        entry.isEnabled = true

        let next = BackupAlarmLogic.nextBackupDate(
            for: entry,
            after: today,
            skippingCurrentOccurrence: false,
            calendar: calendar
        )
        let nextDay = calendar.date(byAdding: .day, value: 7, to: nextWeekday)!
        #expect(next == calendar.date(bySettingHour: 7, minute: 15, second: 0, of: nextDay))
    }
}

// MARK: - Fake

/// 登録された設定をそのまま記録する偽の AlarmKit。
final class RecordingAlarmManager: AlarmManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Alarm.ID: AlarmManager.AlarmConfiguration<CustomAlarmMetadata>] = [:]
    private var canceledIDs: Set<Alarm.ID> = []

    var configurations: [Alarm.ID: AlarmManager.AlarmConfiguration<CustomAlarmMetadata>] {
        lock.withLock { stored }
    }

    var registeredIDs: Set<Alarm.ID> {
        lock.withLock { Set(stored.keys) }
    }

    var canceled: Set<Alarm.ID> {
        lock.withLock { canceledIDs }
    }

    var authorizationState: AlarmManager.AuthorizationState { .authorized }

    func requestAuthorization() async throws -> AlarmManager.AuthorizationState {
        .authorized
    }

    func alarmSnapshots() throws -> [AlarmSnapshot] {
        lock.withLock {
            stored.map { AlarmSnapshot(id: $0.key, state: .scheduled) }
        }
    }

    func schedule(
        id: Alarm.ID,
        configuration: AlarmManager.AlarmConfiguration<CustomAlarmMetadata>
    ) async throws {
        lock.withLock { stored[id] = configuration }
    }

    func cancel(id: Alarm.ID) throws {
        lock.withLock {
            stored.removeValue(forKey: id)
            canceledIDs.insert(id)
        }
    }
}

extension AlarmSchedulerSkipTests {

    @Test
    func globalSkip_removesTheWeekdayAndRestoresAfterUndo() async throws {
        try await withCleanState {
            let fake = RecordingAlarmManager()
            let scheduler = AlarmScheduler(manager: fake)
            let calendar = Calendar.current
            let hour = (calendar.component(.hour, from: Date()) + 1) % 24
            let entry = AlarmEntry(
                hour: hour,
                minute: 0,
                label: "global-skip",
                repeatWeekdays: [1, 2, 3, 4, 5, 6, 7]
            )
            let now = Date()
            AppGroup.globalSkip = GlobalSkip(
                start: now,
                end: calendar.date(byAdding: .day, value: 1, to: now)!,
                entryIDs: [entry.id]
            )

            scheduler.syncAlarms([entry], trigger: .launch)
            await scheduler.waitForPendingSync()

            let weekly = fake.configurations.values.compactMap {
                schedule(of: $0).flatMap(weekdaySet)
            }
            #expect(weekly.count == 1)
            #expect(weekly[0].count == 6)
            #expect(!(AlarmIDMaps.loadSkipCoverage()[entry.id] ?? [:]).isEmpty)

            AppGroup.globalSkip = nil
            scheduler.syncAlarms([entry], trigger: .edit)
            await scheduler.waitForPendingSync()

            let restored = fake.configurations.values.compactMap {
                schedule(of: $0).flatMap(weekdaySet)
            }
            #expect(restored.count == 1)
            #expect(restored[0] == Set([1, 2, 3, 4, 5, 6, 7]))
            #expect((AlarmIDMaps.loadSkipCoverage()[entry.id] ?? [:]).isEmpty)
        }
    }
}
