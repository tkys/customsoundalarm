import Foundation
import AlarmKit
import SwiftUI
import os

// MARK: - TestRingPermission

/// 試しに鳴らすボタンの有効/無効を決めるための権限状態（#109）。
enum TestRingPermission: Equatable, Sendable {
    case unknown
    case allowed
    case denied
}

// MARK: - AlarmScheduler

@Observable
@MainActor
final class AlarmScheduler {
    static let shared = AlarmScheduler()

    private let logger = Logger(subsystem: "com.tkysdev.customsoundalarm", category: "AlarmScheduler")
    private nonisolated(unsafe) let manager = AlarmManager.shared

    private(set) var scheduledAlarmCount: Int = 0

    /// 試しに鳴らすボタンの権限状態（#109）
    private(set) var testRingPermission: TestRingPermission = .unknown

    /// いずれかのアラームが鳴動中か（アップデート案内の抑制・#116）
    private(set) var isAlarmRinging: Bool = false

    /// 試しに鳴らすアラームが登録中/鳴動中か（アップデート案内の抑制・#116）
    var isTestRingActive: Bool {
        !AppGroup.testAlarmRecords.isEmpty
    }

    /// 試しアラームの記録ごとの掃除タスク（60秒後にキャンセルする）
    @ObservationIgnored
    private var testRingCleanupTasks: [UUID: Task<Void, Never>] = [:]

    /// AlarmEntry.id → AlarmKit Alarm.ID のマッピング
    private var alarmIDMap: [UUID: Alarm.ID] = [:]

    /// AlarmEntry.id → 最終アラームの AlarmKit Alarm.ID のマッピング（#110）
    private var backupAlarmIDMap: [UUID: Alarm.ID] = [:]

    /// sync の直列化用（連続操作時に前回をキャンセルして最新のみ実行）
    private var syncTask: Task<Void, Never>?

    /// 状態監視タスク（重複防止用にハンドル保持）
    private var observationTask: Task<Void, Never>?

    /// ID マッピングの永続化キー
    private var idMapKey: String { AlarmIDMaps.primaryKey }

    /// 最終アラームの ID マッピングの永続化キー（#110）
    private var backupIDMapKey: String { AlarmIDMaps.backupKey }

    /// 同一 AlarmEntry.ID に対して alarm_fired を1回だけ送るための記録（observer 系）
    @ObservationIgnored
    private var firedReportedThisSession: Set<Alarm.ID> = []

    /// 最終アラームの backup_alarm_fired を1回だけ送るための記録（#110）
    @ObservationIgnored
    private var backupFiredReportedThisSession: Set<Alarm.ID> = []

    private init() {
        loadIDMap()
        loadBackupIDMap()
        refreshTestRingPermission()
    }

    /// 試しに鳴らすボタンの権限状態を更新する（#109）
    func refreshTestRingPermission() {
        switch manager.authorizationState {
        case .authorized: testRingPermission = .allowed
        case .denied: testRingPermission = .denied
        case .notDetermined: testRingPermission = .unknown
        @unknown default: testRingPermission = .unknown
        }
    }

    /// 試しに鳴らせる状態か（ボタンの有効条件）
    var canScheduleTestRing: Bool {
        testRingPermission == .allowed
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        switch manager.authorizationState {
        case .notDetermined:
            do {
                let state = try await manager.requestAuthorization()
                if state == .authorized {
                    recordPermissionStatus(.authorized)
                    return true
                } else {
                    recordPermissionStatus(.denied)
                    return false
                }
            } catch {
                logger.error("AlarmKit authorization failed: \(error.localizedDescription)")
                recordPermissionStatus(.requestFailed)
                return false
            }
        case .authorized:
            recordPermissionStatus(.authorized)
            return true
        case .denied:
            recordPermissionStatus(.denied)
            return false
        @unknown default:
            recordPermissionStatus(.unknown)
            return false
        }
    }

    /// 権限状態を計測する（#91-2）。
    /// **前回送信時と状態が変わったときだけ**送る（状態を永続化して比較）。
    /// 従来はセッション内メモリ比較だったため実質起動ごとに送信され、
    /// 6.8回/人を消費していた。判定は `AnalyticsThrottle`（純粋関数）。
    private func recordPermissionStatus(_ status: AlarmPermissionStatus) {
        let lastSent = AppGroup.lastReportedPermissionStatus
            .flatMap { AlarmPermissionStatus(rawValue: $0) }
        guard AnalyticsThrottle.shouldSendPermissionStatus(current: status, lastSent: lastSent) else { return }
        AppGroup.lastReportedPermissionStatus = status.rawValue
        AnalyticsService.shared.capture(.alarmPermission(status: status))
    }

    // MARK: - Reconciliation (起動時の整合性チェック)

    /// アプリ起動時に AlarmKit の状態と AlarmStore を突合し、
    /// 発火済みの一回限りアラームを自動 OFF にする
    func reconcileOnLaunch() {
        // 試しのアラームは永続化しない。前回起動時に残っていれば確実にキャンセルする（#109）
        cancelAllTestAlarms()

        let activeAlarmIDs: Set<Alarm.ID>
        do {
            let alarms = try manager.alarms
            activeAlarmIDs = Set(alarms.map(\.id))
            isAlarmRinging = alarms.contains { $0.state == .alerting }
        } catch {
            logger.error("Failed to fetch alarms for reconciliation: \(error.localizedDescription)")
            return
        }

        let store = AlarmStore.shared
        var didChange = false

        for alarm in store.alarms where alarm.isEnabled && alarm.repeatWeekdays.isEmpty {
            if let mappedID = alarmIDMap[alarm.id], !activeAlarmIDs.contains(mappedID) {
                // 発火済みの一回限りアラーム → 遡及記録してから無効化
                AnalyticsService.shared.capture(.alarmFired(
                    wasAppForeground: false,
                    hour: alarm.hour,
                    isRepeating: false,
                    detection: "reconcile"
                ))
                store.toggleEnabled(alarm)
                alarmIDMap.removeValue(forKey: alarm.id)
                if let backupID = backupAlarmIDMap.removeValue(forKey: alarm.id) {
                    try? manager.cancel(id: backupID)
                    logger.info("Reconcile: cancelled backup for one-time alarm: \(alarm.label)")
                }
                var counts = AppGroup.snoozeCounts
                counts.removeValue(forKey: alarm.id)
                AppGroup.snoozeCounts = counts
                didChange = true
                logger.info("Reconcile: one-time alarm auto-disabled: \(alarm.label)")
            }
        }

        if didChange {
            saveIDMap()
            saveBackupIDMap()
        }

        // 最終アラームの整合性（無効/削除されたアラームの取り残しを消す）
        cancelOrphanBackupAlarms(entries: store.alarms)

        // スヌーズ待機中（.countdown）のアラームを遡及記録（App Group 永続化で二重計上防止）
        var snoozedIDs = AppGroup.snoozedAlarmEntryIDs
        for alarm in (try? manager.alarms) ?? [] where alarm.state == .countdown {
            guard let entryID = alarmIDMap.first(where: { $0.value == alarm.id })?.key,
                  !snoozedIDs.contains(entryID)
            else { continue }
            snoozedIDs.insert(entryID)
            var counts = AppGroup.snoozeCounts
            counts[entryID, default: 0] += 1
            AppGroup.snoozeCounts = counts
            AnalyticsService.shared.capture(.alarmSnoozed(from: "reconcile"))
            logger.info("Reconcile: detected snoozing alarm: \(alarm.id)")
        }
        // .countdown でなくなったアラームをクリーンアップ
        let currentCountdownEntryIDs = Set(((try? manager.alarms) ?? []).compactMap { alarm in
            alarm.state == .countdown
                ? alarmIDMap.first(where: { $0.value == alarm.id })?.key
                : nil
        })
        snoozedIDs.formIntersection(currentCountdownEntryIDs)
        AppGroup.snoozedAlarmEntryIDs = snoozedIDs
    }

    // MARK: - Scheduling

    /// 全アラームを同期（直列化: 連続呼び出し時は前回をキャンセルし最新のみ実行）
    func syncAlarms(_ entries: [AlarmEntry]) {
        syncTask?.cancel()
        syncTask = Task {
            await performSync(entries)
        }
    }

    private func performSync(_ entries: [AlarmEntry]) async {
        guard !Task.isCancelled else { return }

        guard await requestAuthorization() else {
            logger.warning("AlarmKit not authorized, skipping alarm sync")
            return
        }

        let activeStates: [Alarm.ID: Alarm.State]
        do {
            activeStates = Dictionary(uniqueKeysWithValues: try manager.alarms.map { ($0.id, $0.state) })
        } catch {
            logger.error("Failed to fetch alarm states: \(error.localizedDescription)")
            return
        }

        let diff = computeSyncDiff(
            oldMap: alarmIDMap,
            entries: entries,
            activeStates: activeStates
        )

        // Cancel alarms for disabled/deleted entries
        for entryID in diff.cancelEntryIDs {
            guard let alarmID = alarmIDMap[entryID] else { continue }
            do {
                try manager.cancel(id: alarmID)
                logger.info("Cancelled alarm for removed entry: \(entryID)")
            } catch {
                logger.error("Failed to cancel alarm \(alarmID): \(error.localizedDescription)")
            }
        }

        // Cancel old alarms for entries being rescheduled (before scheduling new ones)
        for (_, oldAlarmID) in diff.rescheduleAlarmIDs {
            do {
                try manager.cancel(id: oldAlarmID)
                logger.info("Cancelled old alarm for reschedule: \(oldAlarmID)")
            } catch {
                logger.error("Failed to cancel old alarm \(oldAlarmID): \(error.localizedDescription)")
            }
        }

        // Schedule new/changed entries
        var newMap = diff.keptMap
        for entry in diff.scheduleEntries {
            guard !Task.isCancelled else { return }
            if let alarmID = await scheduleAlarm(for: entry) {
                newMap[entry.id] = alarmID
            }
        }

        guard !Task.isCancelled else { return }

        // 最終アラーム（#110）: 本体と必ず一緒に同期する。
        // 停止 Intent が次回分を登録している場合があるので、永続化された最新マップを読む。
        backupAlarmIDMap = AlarmIDMaps.loadBackup()
        let now = Date()
        let suppressedEntryIDs = Set(entries.compactMap { entry -> UUID? in
            guard let canceledAt = AppGroup.backupCanceledAt[entry.id],
                  let nextDate = BackupAlarmLogic.nextBackupDate(
                      for: entry,
                      after: now,
                      skippingCurrentOccurrence: false
                  ),
                  BackupAlarmLogic.isSuppressed(nextFireDate: nextDate, canceledAt: canceledAt)
            else { return nil }
            return entry.id
        })

        let backupDiff = BackupAlarmLogic.computeBackupSyncDiff(
            oldMap: backupAlarmIDMap,
            entries: entries,
            activeStates: activeStates,
            suppressedEntryIDs: suppressedEntryIDs
        )

        for entryID in backupDiff.cancelEntryIDs {
            guard let backupID = backupAlarmIDMap[entryID] else { continue }
            try? manager.cancel(id: backupID)
            logger.info("Cancelled backup alarm for removed entry: \(entryID)")
        }
        for (_, oldBackupID) in backupDiff.rescheduleAlarmIDs {
            try? manager.cancel(id: oldBackupID)
        }

        var newBackupMap = backupDiff.keptMap
        for entry in backupDiff.scheduleEntries {
            guard !Task.isCancelled else { return }
            if let backupID = await scheduleBackupAlarm(for: entry) {
                newBackupMap[entry.id] = backupID
            }
        }

        guard !Task.isCancelled else { return }

        alarmIDMap = newMap
        backupAlarmIDMap = newBackupMap
        scheduledAlarmCount = newMap.count
        saveIDMap()
        saveBackupIDMap()

        logger.info("Synced \(self.scheduledAlarmCount) alarms (\(diff.keptMap.count) kept, \(diff.scheduleEntries.count) scheduled, \(diff.cancelEntryIDs.count) cancelled, \(diff.rescheduleAlarmIDs.count) rescheduled), backups: \(newBackupMap.count)")
    }

    /// 単一アラームをスケジュール（成功時に Alarm.ID を返す）
    private func scheduleAlarm(for entry: AlarmEntry) async -> Alarm.ID? {
        let displayName = SoundStore.shared.displayName(for: entry.soundFileName)
        let metadata = CustomAlarmMetadata(entry: entry, soundDisplayName: displayName)

        let hasSnooze = entry.snoozeMinutes > 0

        let alert: AlarmPresentation.Alert
        if hasSnooze {
            if #available(iOS 26.1, *) {
                alert = AlarmPresentation.Alert(
                    title: LocalizedStringResource(stringLiteral: entry.label),
                    secondaryButton: AlarmButton(
                        text: "snooze",
                        textColor: .blue,
                        systemImageName: "clock.fill"
                    ),
                    secondaryButtonBehavior: .countdown
                )
            } else {
                alert = AlarmPresentation.Alert(
                    title: LocalizedStringResource(stringLiteral: entry.label),
                    stopButton: AlarmButton(
                        text: "stop_alarm",
                        textColor: .red,
                        systemImageName: "stop.fill"
                    ),
                    secondaryButton: AlarmButton(
                        text: "snooze",
                        textColor: .blue,
                        systemImageName: "clock.fill"
                    ),
                    secondaryButtonBehavior: .countdown
                )
            }
        } else {
            if #available(iOS 26.1, *) {
                alert = AlarmPresentation.Alert(
                    title: LocalizedStringResource(stringLiteral: entry.label)
                )
            } else {
                alert = AlarmPresentation.Alert(
                    title: LocalizedStringResource(stringLiteral: entry.label),
                    stopButton: AlarmButton(
                        text: "stop_alarm",
                        textColor: .red,
                        systemImageName: "stop.fill"
                    )
                )
            }
        }

        let countdownPresentation: AlarmPresentation.Countdown?
        if hasSnooze {
            countdownPresentation = AlarmPresentation.Countdown(
                title: LocalizedStringResource(stringLiteral: entry.label),
                pauseButton: nil
            )
        } else {
            countdownPresentation = nil
        }

        let attributes = AlarmAttributes<CustomAlarmMetadata>(
            presentation: AlarmPresentation(
                alert: alert,
                countdown: countdownPresentation,
                paused: nil
            ),
            metadata: metadata,
            tintColor: .orange
        )

        let alarmTime = Alarm.Schedule.Relative.Time(
            hour: entry.hour,
            minute: entry.minute
        )

        let schedule: Alarm.Schedule
        if entry.repeatWeekdays.isEmpty {
            schedule = .relative(.init(time: alarmTime, repeats: .never))
        } else {
            let weekdays = entry.repeatWeekdays.compactMap { dayInt -> Locale.Weekday? in
                switch dayInt {
                case 1: .sunday
                case 2: .monday
                case 3: .tuesday
                case 4: .wednesday
                case 5: .thursday
                case 6: .friday
                case 7: .saturday
                default: nil
                }
            }
            let recurrence = Alarm.Schedule.Relative.Recurrence.weekly(weekdays)
            schedule = .relative(.init(time: alarmTime, repeats: recurrence))
        }

        let countdownDuration: Alarm.CountdownDuration?
        if hasSnooze {
            #if DEBUG
            let useSeconds = UserDefaults.standard.bool(forKey: "SnoozeDebugUseSeconds")
            #else
            let useSeconds = false
            #endif
            countdownDuration = Alarm.CountdownDuration(
                preAlert: nil,
                postAlert: snoozeInterval(minutes: entry.snoozeMinutes, useSeconds: useSeconds)
            )
        } else {
            countdownDuration = nil
        }

        let alarmID = Alarm.ID()
        let config = AlarmManager.AlarmConfiguration<CustomAlarmMetadata>(
            countdownDuration: countdownDuration,
            schedule: schedule,
            attributes: attributes,
            stopIntent: DismissAlarmIntent(alarmID: alarmID.uuidString),
            sound: entry.soundFileName.isEmpty ? .default : .named(entry.soundFileName)
        )

        do {
            _ = try await manager.schedule(id: alarmID, configuration: config)
            // 新しい発火サイクルなのでスヌーズ回数をリセット（#110）
            var counts = AppGroup.snoozeCounts
            if counts.removeValue(forKey: entry.id) != nil {
                AppGroup.snoozeCounts = counts
            }
            logger.info("Scheduled alarm: \(entry.timeString) - \(entry.label)")
            return alarmID
        } catch {
            logger.error("Failed to schedule alarm \(entry.label): \(error.localizedDescription)")
            return nil
        }
    }

    /// 最終アラームを登録（停止のみ・スヌーズなし・次の1回だけ）（#110）
    private func scheduleBackupAlarm(for entry: AlarmEntry) async -> Alarm.ID? {
        guard entry.backupMinutes != nil else { return nil }

        let now = Date()
        let nextDate = BackupAlarmLogic.nextBackupDate(
            for: entry,
            after: now,
            skippingCurrentOccurrence: false
        )
        guard let nextDate else { return nil }

        // 停止で取り消した締め切りを、次回同期で復活させない（#110）
        if let canceledAt = AppGroup.backupCanceledAt[entry.id],
           BackupAlarmLogic.isSuppressed(nextFireDate: nextDate, canceledAt: canceledAt) {
            logger.info("Backup suppressed after stop: \(entry.label)")
            return nil
        }

        let alarmID = Alarm.ID()
        let displayName = SoundStore.shared.displayName(for: entry.soundFileName)
        let config = BackupAlarmFactory.configuration(
            for: entry,
            fireDate: nextDate,
            alarmID: alarmID,
            displayName: displayName
        )

        do {
            _ = try await manager.schedule(id: alarmID, configuration: config)
            logger.info("Scheduled one-shot backup alarm at \(nextDate) for \(entry.label)")
            return alarmID
        } catch {
            logger.error("Failed to schedule backup alarm \(entry.label): \(error.localizedDescription)")
            return nil
        }
    }

    /// 無効/削除されたアラームの最終アラームを取り残さない（起動時の整合性）。
    private func cancelOrphanBackupAlarms(entries: [AlarmEntry]) {
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        var orphanIDs: [UUID] = []
        for (entryID, _) in backupAlarmIDMap {
            guard let entry = byID[entryID], entry.isEnabled, entry.backupMinutes != nil else {
                orphanIDs.append(entryID)
                continue
            }
        }
        guard !orphanIDs.isEmpty else { return }
        for entryID in orphanIDs {
            if let backupID = backupAlarmIDMap.removeValue(forKey: entryID) {
                try? manager.cancel(id: backupID)
            }
        }
        saveBackupIDMap()
        logger.info("Cancelled \(orphanIDs.count) orphan backup alarm(s)")
    }

    // MARK: - Test Ring (#109)

    /// 選択中のサウンド（または最終アラーム用の音）で 5 秒後に一度だけ鳴らす。
    /// AlarmStore には保存しない。成功したら ID を AppGroup に記録し、
    /// 停止・60 秒経過・次回起動時でキャンセルする。
    /// - Returns: 登録できたら true
    @discardableResult
    func scheduleTestRing(soundFileName: String, kind: TestRingKind, now: Date = Date()) async -> Bool {
        refreshTestRingPermission()
        guard canScheduleTestRing else {
            logger.warning("Test ring skipped: AlarmKit not authorized")
            return false
        }

        #if targetEnvironment(simulator)
        // シミュレータで AlarmKit を鳴らすと SpringBoard が落ちるため登録しない。
        // 鳴動確認は実機で行う（#109）。
        logger.warning("Test ring is disabled on the simulator")
        return false
        #else
        let plan = TestRingLogic.makePlan(now: now, soundFileName: soundFileName, kind: kind)
        let alarmID = UUID()
        let config = makeTestRingConfiguration(for: plan, alarmID: alarmID)

        do {
            _ = try await manager.schedule(id: alarmID, configuration: config)
            var records = AppGroup.testAlarmRecords
            records.append(TestAlarmRecord(id: alarmID, scheduledAt: now, kind: kind))
            AppGroup.testAlarmRecords = records
            AnalyticsService.shared.capture(.testRingScheduled(kind: kind))
            scheduleTestRingCleanup(for: alarmID)
            logger.info("Scheduled test ring in \(TestRingLogic.delay)s (kind=\(kind.rawValue))")
            return true
        } catch {
            logger.error("Failed to schedule test ring: \(error.localizedDescription)")
            return false
        }
        #endif
    }

    /// 試しアラーム用の AlarmKit 設定（一回限り・スヌーズなし・停止のみ）。
    private func makeTestRingConfiguration(
        for plan: TestRingLogic.Plan,
        alarmID: UUID
    ) -> AlarmManager.AlarmConfiguration<CustomAlarmMetadata> {
        let title = LocalizedStringResource("test_ring_alarm_title")
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: title)
        } else {
            alert = AlarmPresentation.Alert(
                title: title,
                stopButton: AlarmButton(
                    text: "stop_alarm",
                    textColor: .red,
                    systemImageName: "stop.fill"
                )
            )
        }
        let attributes = AlarmAttributes<CustomAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert, countdown: nil, paused: nil),
            metadata: CustomAlarmMetadata(),
            tintColor: .orange
        )
        return AlarmManager.AlarmConfiguration(
            countdownDuration: nil,
            schedule: .fixed(plan.fireDate),
            attributes: attributes,
            stopIntent: DismissAlarmIntent(alarmID: alarmID.uuidString),
            sound: plan.soundFileName.isEmpty ? .default : .named(plan.soundFileName)
        )
    }

    /// 60 秒経過した試しアラームをキャンセルして記録から消す。
    func cleanupTestAlarms(now: Date = Date()) {
        let records = AppGroup.testAlarmRecords
        guard !records.isEmpty else { return }

        let result = TestRingLogic.cleanup(records: records, now: now)
        for id in result.expiredIDs {
            try? manager.cancel(id: id)
        }
        if !result.expiredIDs.isEmpty {
            AppGroup.testAlarmRecords = result.remaining
            logger.info("Cleaned up \(result.expiredIDs.count) test ring alarm(s)")
        }
    }

    /// 起動時に残っている試しアラームをすべてキャンセルする。
    private func cancelAllTestAlarms() {
        let records = AppGroup.testAlarmRecords
        guard !records.isEmpty else { return }
        for record in records {
            try? manager.cancel(id: record.id)
        }
        AppGroup.testAlarmRecords = []
        logger.info("Cancelled \(records.count) leftover test ring alarm(s)")
    }

    /// 鳴らした試しアラームを 60 秒後に掃除する（放置対策）。
    private func scheduleTestRingCleanup(for alarmID: UUID) {
        testRingCleanupTasks[alarmID]?.cancel()
        testRingCleanupTasks[alarmID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(TestRingLogic.cleanupAfter + 1))
            guard !Task.isCancelled else { return }
            self?.cleanupTestAlarms()
            self?.testRingCleanupTasks[alarmID] = nil
        }
    }

    // MARK: - Alarm State Observation

    /// アラーム状態の監視を開始（重複呼び出し時は前回をキャンセル）
    func startObservingAlarmStates() {
        observationTask?.cancel()
        observationTask = Task {
            for await alarms in manager.alarmUpdates {
                guard !Task.isCancelled else { break }
                isAlarmRinging = alarms.contains { $0.state == .alerting }
                for alarm in alarms {
                    switch alarm.state {
                    case .alerting:
                        logger.info("Alarm alerting: \(alarm.id)")
                        handleAlarmFired(alarmKitID: alarm.id)
                    case .countdown:
                        // スヌーズ待機中への遷移を検知（App Group 永続化で二重計上防止）
                        guard let entryID = alarmIDMap.first(where: { $0.value == alarm.id })?.key else { continue }
                        var snoozedIDs = AppGroup.snoozedAlarmEntryIDs
                        guard !snoozedIDs.contains(entryID) else { continue }
                        snoozedIDs.insert(entryID)
                        AppGroup.snoozedAlarmEntryIDs = snoozedIDs
                        var counts = AppGroup.snoozeCounts
                        counts[entryID, default: 0] += 1
                        AppGroup.snoozeCounts = counts
                        logger.info("Alarm snoozed: \(alarm.id)")
                        AnalyticsService.shared.capture(.alarmSnoozed(from: "observer"))
                    default:
                        // スヌーズ解除の検知: .countdown でなくなったアラームをクリーンアップ
                        guard let entryID = alarmIDMap.first(where: { $0.value == alarm.id })?.key else { continue }
                        var snoozedIDs = AppGroup.snoozedAlarmEntryIDs
                        if snoozedIDs.remove(entryID) != nil {
                            AppGroup.snoozedAlarmEntryIDs = snoozedIDs
                        }
                    }
                }
            }
        }
    }

    /// 一回限りアラーム発火後に isEnabled を false にする
    private func handleAlarmFired(alarmKitID: Alarm.ID) {
        // 定着ユーザー判定用に発火実績を記録（同一日は1回、鳴動中は毎tick呼ばれるが日単位で冪等）
        // マッピング欠落時（オーファン）でも呼び出す
        ReviewRequestManager.shared.recordAlarmFired()

        // 最終アラームの発火（#110）。本体の store には触らない
        if let backupEntryID = backupAlarmIDMap.first(where: { $0.value == alarmKitID })?.key {
            if !backupFiredReportedThisSession.contains(alarmKitID) {
                backupFiredReportedThisSession.insert(alarmKitID)
                AnalyticsService.shared.capture(.backupAlarmFired(
                    snoozesBefore: AppGroup.snoozeCounts[backupEntryID]
                ))
                logger.info("Final alarm fired: \(alarmKitID)")
            }
            return
        }

        guard let entryID = alarmIDMap.first(where: { $0.value == alarmKitID })?.key else {
            return
        }

        let store = AlarmStore.shared
        guard let alarm = store.alarms.first(where: { $0.id == entryID }) else {
            return
        }

        // alarm_fired 計測（同一 Alarm.ID につきセッション中1回のみ）
        if !firedReportedThisSession.contains(alarmKitID) {
            firedReportedThisSession.insert(alarmKitID)
            AnalyticsService.shared.capture(.alarmFired(
                wasAppForeground: true,
                hour: alarm.hour,
                isRepeating: !alarm.repeatWeekdays.isEmpty,
                detection: "observer"
            ))
        }

        if alarm.repeatWeekdays.isEmpty && alarm.isEnabled {
            store.toggleEnabled(alarm)
            alarmIDMap.removeValue(forKey: entryID)
            saveIDMap()
            logger.info("One-time alarm fired, auto-disabled: \(alarm.label)")
        }
    }

    // MARK: - ID Map Persistence

    private func saveIDMap() {
        do {
            let data = try JSONEncoder().encode(alarmIDMap)
            AppGroup.userDefaults.set(data, forKey: idMapKey)
        } catch {
            logger.error("Failed to save alarm ID map: \(error.localizedDescription)")
        }
    }

    private func loadIDMap() {
        guard let data = AppGroup.userDefaults.data(forKey: idMapKey) else { return }
        do {
            alarmIDMap = try JSONDecoder().decode([UUID: Alarm.ID].self, from: data)
            logger.info("Loaded alarm ID map with \(self.alarmIDMap.count) entries")
        } catch {
            logger.warning("Failed to decode alarm ID map, starting fresh")
            alarmIDMap = [:]
        }
    }

    private func saveBackupIDMap() {
        do {
            let data = try JSONEncoder().encode(backupAlarmIDMap)
            AppGroup.userDefaults.set(data, forKey: backupIDMapKey)
        } catch {
            logger.error("Failed to save backup alarm ID map: \(error.localizedDescription)")
        }
    }

    private func loadBackupIDMap() {
        guard let data = AppGroup.userDefaults.data(forKey: backupIDMapKey) else { return }
        do {
            backupAlarmIDMap = try JSONDecoder().decode([UUID: Alarm.ID].self, from: data)
            logger.info("Loaded backup alarm ID map with \(self.backupAlarmIDMap.count) entries")
        } catch {
            logger.warning("Failed to decode backup alarm ID map, starting fresh")
            backupAlarmIDMap = [:]
        }
    }
}

// MARK: - SyncDiff

/// 差分同期のための計算結果。`computeSyncDiff` が返す。
struct SyncDiff: Sendable {
    /// 保護状態のためマップに残す entryID → Alarm.ID
    var keptMap: [UUID: Alarm.ID]
    /// 削除/無効化されたためキャンセルが必要な entryID
    var cancelEntryIDs: Set<UUID>
    /// 再スケジュール前にキャンセルすべき旧 Alarm（scheduleEntries のうち oldMap に存在したもの）
    var rescheduleAlarmIDs: [UUID: Alarm.ID]
    /// 新規または変更があったためスケジュールが必要な AlarmEntry
    var scheduleEntries: [AlarmEntry]
}

/// 差分同期のための alarmIDMap 遷移を計算する純粋関数。
/// 副作用がなく、単体テスト可能。
func computeSyncDiff(
    oldMap: [UUID: Alarm.ID],
    entries: [AlarmEntry],
    activeStates: [Alarm.ID: Alarm.State]
) -> SyncDiff {
    let enabledEntryIDs = Set(entries.filter(\.isEnabled).map(\.id))
    var keptMap: [UUID: Alarm.ID] = [:]
    var cancelEntryIDs = Set<UUID>()
    var rescheduleAlarmIDs: [UUID: Alarm.ID] = [:]
    var scheduleEntries: [AlarmEntry] = []

    for entryID in oldMap.keys where !enabledEntryIDs.contains(entryID) {
        cancelEntryIDs.insert(entryID)
    }

    for entry in entries where entry.isEnabled {
        if let alarmID = oldMap[entry.id],
           let state = activeStates[alarmID],
           state == .countdown || state == .alerting || state == .paused {
            keptMap[entry.id] = alarmID
        } else {
            if let oldAlarmID = oldMap[entry.id] {
                rescheduleAlarmIDs[entry.id] = oldAlarmID
            }
            scheduleEntries.append(entry)
        }
    }

    return SyncDiff(
        keptMap: keptMap,
        cancelEntryIDs: cancelEntryIDs,
        rescheduleAlarmIDs: rescheduleAlarmIDs,
        scheduleEntries: scheduleEntries
    )
}
