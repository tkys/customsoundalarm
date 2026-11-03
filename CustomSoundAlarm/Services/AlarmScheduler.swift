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

/// 試し鳴らしの登録結果（#150）。
/// 失敗時は理由を添え、画面のその場表示と `test_ring_failed` 計測に使う。
enum TestRingResult: Equatable, Sendable {
    case scheduled
    case failed(TestRingFailureReason)
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

    /// 延期した作り直しの再試行（#163）。アプリが生きている間のベストエフォート。
    private var deferredRetryTask: Task<Void, Never>?

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
        #if DEBUG
        if let override = Self.uiTestPermissionOverride {
            testRingPermission = override
            return
        }
        #endif
        switch manager.authorizationState {
        case .authorized: testRingPermission = .allowed
        case .denied: testRingPermission = .denied
        case .notDetermined: testRingPermission = .unknown
        @unknown default: testRingPermission = .unknown
        }
    }

    #if DEBUG
    /// UIテスト用: 「今すぐ鳴らす」の権限状態を強制する（#150）。
    /// 引数なしなら nil（実際の状態を使う）。
    static var uiTestPermissionOverride: TestRingPermission? {
        if CommandLine.arguments.contains("-uitest-test-ring-denied") { return .denied }
        if CommandLine.arguments.contains("-uitest-test-ring-not-determined") { return .unknown }
        return nil
    }
    #endif

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
                    detection: "reconcile",
                    soundMode: AlarmSoundModeResolver.soundMode(for: alarm)
                ))
                store.toggleEnabled(alarm)
                alarmIDMap.removeValue(forKey: alarm.id)
                var primaryNames = AppGroup.primarySoundNames
                primaryNames.removeValue(forKey: alarm.id)
                AppGroup.primarySoundNames = primaryNames
                if let backupID = backupAlarmIDMap.removeValue(forKey: alarm.id) {
                    try? manager.cancel(id: backupID)
                    var soundNames = AppGroup.backupSoundNames
                    soundNames.removeValue(forKey: alarm.id)
                    AppGroup.backupSoundNames = soundNames
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
    func syncAlarms(
        _ entries: [AlarmEntry],
        forceRescheduleEntryIDs: Set<UUID> = [],
        editedEntryIDs: Set<UUID> = [],
        trigger: AlarmSyncTrigger
    ) {
        syncTask?.cancel()
        syncTask = Task {
            await performSync(
                entries,
                forceRescheduleEntryIDs: forceRescheduleEntryIDs,
                editedEntryIDs: editedEntryIDs,
                trigger: trigger
            )
        }
    }

    /// プレイリストの編集・音削除後に、そのプレイリストを使うアラームを再登録する（#160）。
    func resync(entriesUsingPlaylist playlistID: UUID) {
        let entries = AlarmStore.shared.alarms
        let entryIDs = PlaylistResyncLogic.entryIDs(
            entries: entries,
            playlistID: playlistID
        )
        guard !entryIDs.isEmpty else { return }
        syncAlarms(
            entries,
            forceRescheduleEntryIDs: entryIDs,
            trigger: .playlist
        )
    }

    private func performSync(
        _ entries: [AlarmEntry],
        forceRescheduleEntryIDs: Set<UUID> = [],
        editedEntryIDs: Set<UUID> = [],
        trigger: AlarmSyncTrigger
    ) async {
        guard !Task.isCancelled else { return }

        // 現在 AlarmKit に登録中のファイル名を渡し、鳴らす予定のファイルを消さない（#151）
        let registeredSoundFileNames = Set(AppGroup.primarySoundNames.values)
            .union(AppGroup.backupSoundNames.values)
        PlaylistRenderService.shared.cleanupUnusedFiles(
            inputs: entries.map(\.playlistRenderInput),
            keeping: registeredSoundFileNames
        )

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

        // 停止時に発火分のため延期したシャッフル順の作り直し（#163）
        let enabledEntryIDs = Set(entries.filter(\.isEnabled).map(\.id))
        var pendingShuffleRefresh = AppGroup.pendingShuffleRefreshEntryIDs
        pendingShuffleRefresh.formIntersection(enabledEntryIDs)
        AppGroup.pendingShuffleRefreshEntryIDs = pendingShuffleRefresh
        // バックグラウンド起動（intent）では新しい順番の書き出しをせず、
        // 前面復帰か次の同期に回す（#163 レビュー）。
        let pendingShuffleForThisSync = trigger == .intent
            ? Set<UUID>()
            : pendingShuffleRefresh
        var effectiveForceEntryIDs = forceRescheduleEntryIDs
        effectiveForceEntryIDs.formUnion(pendingShuffleForThisSync)

        // 署名計算（#163）。プレイリストは内容が変わっていなければキャッシュを使う。
        // 計測イベントは実際に登録するときだけ送る（reportEvents: false）。
        var desiredSignatures: [UUID: AlarmScheduleSignature] = [:]
        for entry in entries where entry.isEnabled {
            guard !Task.isCancelled else { return }
            if trigger == .intent {
                // バックグラウンド起動では描画しない。キャッシュがあればその署名、
                // 無ければ署名を作らず既存の登録を維持する。
                if let soundFileName = PlaylistRenderService.shared.cachedSoundFileName(
                    for: entry.playlistRenderInput
                ) {
                    desiredSignatures[entry.id] = AlarmScheduleSignature(
                        entry: entry,
                        soundFileName: soundFileName,
                        displayName: soundDisplayName(for: entry)
                    )
                }
                continue
            }
            let resolution = await PlaylistRenderService.shared.prepareSound(
                for: entry.playlistRenderInput,
                forceNewOrder: pendingShuffleForThisSync.contains(entry.id),
                reportEvents: false
            )
            desiredSignatures[entry.id] = AlarmScheduleSignature(
                entry: entry,
                soundFileName: resolution.fileName,
                displayName: soundDisplayName(for: entry)
            )
        }

        let syncNow = Date()
        let diff = computeSyncDiff(
            oldMap: alarmIDMap,
            entries: entries,
            activeStates: activeStates,
            forceRescheduleEntryIDs: effectiveForceEntryIDs,
            signatures: AppGroup.primaryAlarmSignatures,
            desiredSignatures: desiredSignatures,
            editedEntryIDs: editedEntryIDs,
            now: syncNow
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

        // Cancel old alarms for entries being rescheduled (before scheduling new ones).
        // プレイリストのアラームは、新しい登録に成功するまで古い方を残す
        // （差し替えに失敗しても前の音で鳴る・#151）。
        let playlistEntryIDs = Set(
            entries.filter(\.usesPlaylistFeatures).map(\.id)
        )
        var deferredOldAlarmIDs: [UUID: Alarm.ID] = [:]
        for (entryID, oldAlarmID) in diff.rescheduleAlarmIDs {
            if playlistEntryIDs.contains(entryID) {
                deferredOldAlarmIDs[entryID] = oldAlarmID
                continue
            }
            do {
                try manager.cancel(id: oldAlarmID)
                logger.info("Cancelled old alarm for reschedule: \(oldAlarmID)")
            } catch {
                logger.error("Failed to cancel old alarm \(oldAlarmID): \(error.localizedDescription)")
            }
        }

        // 無効・削除されたアラームの登録中ファイル名を落とす（掃除は次回同期で行う）
        let enabledIDs = enabledEntryIDs
        let backupIDs = Set(
            entries.filter { $0.isEnabled && $0.backupMinutes != nil }.map(\.id)
        )
        var primaryNames = AppGroup.primarySoundNames
        primaryNames = primaryNames.filter { enabledIDs.contains($0.key) }
        AppGroup.primarySoundNames = primaryNames
        var backupNames = AppGroup.backupSoundNames
        backupNames = backupNames.filter { backupIDs.contains($0.key) }
        AppGroup.backupSoundNames = backupNames

        // Schedule new/changed entries
        var newMap = diff.keptMap
        var newlyScheduledIDs = Set<UUID>()
        for entry in diff.scheduleEntries {
            guard !Task.isCancelled else { return }
            if let alarmID = await scheduleAlarm(for: entry) {
                newMap[entry.id] = alarmID
                newlyScheduledIDs.insert(entry.id)
                if let oldAlarmID = deferredOldAlarmIDs.removeValue(forKey: entry.id) {
                    try? manager.cancel(id: oldAlarmID)
                }
            } else if let oldAlarmID = deferredOldAlarmIDs[entry.id] {
                // 新しい登録に失敗したので、前のアラームを残す（#151）
                newMap[entry.id] = oldAlarmID
                AnalyticsService.shared.capture(.playlistRescheduleFailed(
                    reason: "schedule_failed"
                ))
                logger.warning("Reschedule failed; keeping previous alarm for entry: \(entry.id)")
            }
        }

        guard !Task.isCancelled else { return }

        // 署名の保存（#163）。延期・鳴動中のエントリは古い署名を残す。
        var primarySignatures = AppGroup.primaryAlarmSignatures
        primarySignatures = primarySignatures.filter { enabledIDs.contains($0.key) }
        for (entryID, signature) in diff.signatureUpdates {
            primarySignatures[entryID] = signature
        }
        AppGroup.primaryAlarmSignatures = primarySignatures

        // 作り直しが完了したシャッフル順の待ちを外す（延期・失敗は残す）
        AppGroup.pendingShuffleRefreshEntryIDs = pendingShuffleRefresh
            .subtracting(newlyScheduledIDs)

        // 最終アラーム（#110）: 本体と必ず一緒に同期する。
        // 停止 Intent が次回分を登録している場合があるので、永続化された最新マップを読む。
        backupAlarmIDMap = AlarmIDMaps.loadBackup()
        let backupNow = Date()
        let suppressedEntryIDs = Set(entries.compactMap { entry -> UUID? in
            guard let canceledAt = AppGroup.backupCanceledAt[entry.id],
                  let nextDate = BackupAlarmLogic.nextBackupDate(
                      for: entry,
                      after: backupNow,
                      skippingCurrentOccurrence: false
                  ),
                  BackupAlarmLogic.isSuppressed(nextFireDate: nextDate, canceledAt: canceledAt)
            else { return nil }
            return entry.id
        })

        // 生成方式の版が古い .loud.caf は次の同期で作り直す（#134）。
        // プレイリストの寝過ごし防止も、存在する最初の曲の「大きくした版」を使う（#151）。
        for entry in entries where entry.isEnabled && entry.backupMinutes != nil {
            if let source = backupSourceFileName(for: entry), !source.isEmpty {
                _ = await BackupLoudVariantService.ensureVariant(for: source)
            }
        }

        var desiredBackupSignatures: [UUID: BackupAlarmScheduleSignature] = [:]
        for entry in entries where entry.isEnabled && entry.backupMinutes != nil {
            guard let nextDate = BackupAlarmLogic.nextBackupDate(
                for: entry,
                after: backupNow,
                skippingCurrentOccurrence: false
            ) else { continue }
            let source = backupSourceFileName(for: entry) ?? ""
            let soundFileName = BackupLoudVariantService.resolvedSoundFileName(
                forSourceFileName: source
            )
            desiredBackupSignatures[entry.id] = BackupAlarmScheduleSignature(
                entry: entry,
                fireDate: nextDate,
                soundFileName: soundFileName
            )
        }

        let backupDiff = BackupAlarmLogic.computeBackupSyncDiff(
            oldMap: backupAlarmIDMap,
            entries: entries,
            activeStates: activeStates,
            suppressedEntryIDs: suppressedEntryIDs,
            forceRescheduleEntryIDs: effectiveForceEntryIDs,
            signatures: AppGroup.backupAlarmSignatures,
            desiredSignatures: desiredBackupSignatures
        )

        for entryID in backupDiff.cancelEntryIDs {
            guard let backupID = backupAlarmIDMap[entryID] else { continue }
            try? manager.cancel(id: backupID)
            var soundNames = AppGroup.backupSoundNames
            soundNames.removeValue(forKey: entryID)
            AppGroup.backupSoundNames = soundNames
            logger.info("Cancelled backup alarm for removed entry: \(entryID)")
        }
        for (_, oldBackupID) in backupDiff.rescheduleAlarmIDs {
            try? manager.cancel(id: oldBackupID)
        }

        var newBackupMap = backupDiff.keptMap
        var newlyScheduledBackupIDs = Set<UUID>()
        for entry in backupDiff.scheduleEntries {
            guard !Task.isCancelled else { return }
            if let backupID = await scheduleBackupAlarm(for: entry) {
                newBackupMap[entry.id] = backupID
                newlyScheduledBackupIDs.insert(entry.id)
            }
        }

        guard !Task.isCancelled else { return }

        // 最終アラームの署名保存（#163）
        var backupSignatures = AppGroup.backupAlarmSignatures
        backupSignatures = backupSignatures.filter { backupIDs.contains($0.key) }
        for (entryID, signature) in backupDiff.signatureUpdates {
            backupSignatures[entryID] = signature
        }
        for entryID in newlyScheduledBackupIDs {
            if let signature = desiredBackupSignatures[entryID] {
                backupSignatures[entryID] = signature
            }
        }
        AppGroup.backupAlarmSignatures = backupSignatures

        alarmIDMap = newMap
        backupAlarmIDMap = newBackupMap
        scheduledAlarmCount = newMap.count
        saveIDMap()
        saveBackupIDMap()

        // 同期の記録（#163）。原因切り分け用に最新50件を残す。
        // 実際に登録できたものだけを「作り直した」として数える。
        let allReasons = Array(diff.rescheduleReasons.filter {
            newlyScheduledIDs.contains($0.key)
        }.values)
            + Array(backupDiff.rescheduleReasons.filter {
                newlyScheduledBackupIDs.contains($0.key)
            }.values)
        let changedCount = allReasons.filter { $0 == .changed }.count
        let missingCount = allReasons.filter { $0 == .missing }.count
        let forcedCount = allReasons.filter { $0 == .forced }.count
        let rescheduledCount = allReasons.count
        let deferredCount = diff.deferredEntryIDs.count

        if rescheduledCount > 0 {
            AnalyticsService.shared.capture(.alarmSyncRescheduled(
                trigger: trigger,
                changed: changedCount,
                missing: missingCount,
                forced: forcedCount
            ))
        }
        if deferredCount > 0 {
            AnalyticsService.shared.capture(.alarmSyncDeferred(
                trigger: trigger,
                count: deferredCount
            ))
            scheduleDeferredRetry()
        } else {
            deferredRetryTask?.cancel()
            deferredRetryTask = nil
        }

        let logEntry = AlarmSyncLogEntry(
            trigger: trigger,
            timestamp: Date(),
            rescheduledCount: rescheduledCount,
            deferredCount: deferredCount,
            changedCount: changedCount,
            missingCount: missingCount,
            forcedCount: forcedCount
        )
        AppGroup.alarmSyncLog = AlarmSyncLog.appending(
            logEntry,
            to: AppGroup.alarmSyncLog
        )

        logger.info("Synced \(self.scheduledAlarmCount) alarms (\(diff.keptMap.count) kept, \(diff.scheduleEntries.count) scheduled, \(diff.cancelEntryIDs.count) cancelled, \(diff.rescheduleAlarmIDs.count) rescheduled, \(deferredCount) deferred, trigger: \(trigger.rawValue)), backups: \(newBackupMap.count)")
    }

    /// 延期した作り直しを90秒後に再試行する（#163）。
    /// 分が変わった後のベストエフォート。アプリが停止・終了したら次回起動時に任せる。
    private func scheduleDeferredRetry() {
        deferredRetryTask?.cancel()
        deferredRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(90))
            guard !Task.isCancelled else { return }
            self?.syncAlarms(
                AlarmStore.shared.alarms,
                trigger: .deferredRetry
            )
        }
    }

    /// 単一アラームをスケジュール（成功時に Alarm.ID を返す）
    private func scheduleAlarm(for entry: AlarmEntry) async -> Alarm.ID? {
        let resolution = await PlaylistRenderService.shared.prepareSound(
            for: entry.playlistRenderInput
        )
        let alarmID = Alarm.ID()
        // AlarmKit の設定は値型のみで不変。SDK の nonisolated API に渡すため
        // 明示的に unsafe を付ける（既存の scheduleAlarm と同じ扱い）。
        nonisolated(unsafe) let config = makeAlarmConfiguration(
            for: entry,
            soundFileName: resolution.fileName,
            displayName: soundDisplayName(for: entry),
            alarmID: alarmID
        )

        do {
            _ = try await manager.schedule(id: alarmID, configuration: config)
            var names = AppGroup.primarySoundNames
            names[entry.id] = resolution.fileName
            AppGroup.primarySoundNames = names
            // 実際に登録した内容の署名を保存する（#163）
            var signatures = AppGroup.primaryAlarmSignatures
            signatures[entry.id] = AlarmScheduleSignature(
                entry: entry,
                soundFileName: resolution.fileName,
                displayName: soundDisplayName(for: entry)
            )
            AppGroup.primaryAlarmSignatures = signatures
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

    /// AlarmKit の設定を組み立てる（通常同期と停止後の再登録で共用）。
    private func makeAlarmConfiguration(
        for entry: AlarmEntry,
        soundFileName: String,
        displayName: String,
        alarmID: Alarm.ID
    ) -> AlarmManager.AlarmConfiguration<CustomAlarmMetadata> {
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

        return AlarmManager.AlarmConfiguration<CustomAlarmMetadata>(
            countdownDuration: countdownDuration,
            schedule: schedule,
            attributes: attributes,
            stopIntent: DismissAlarmIntent(alarmID: alarmID.uuidString),
            sound: soundFileName.isEmpty ? .default : .named(soundFileName)
        )
    }

    /// プレイリストのバックアップ用に、存在する最初の曲を返す（#151）。
    func backupSourceFileName(for entry: AlarmEntry) -> String? {
        if entry.playlistID != nil {
            let playlist = PlaylistStore.shared.playlist(id: entry.playlistID)
            if let track = playlist?.tracks.first(where: {
                soundFileExists($0.soundFileName)
            }) {
                return track.soundFileName
            }
            return soundFileExists(entry.soundFileName) ? entry.soundFileName : nil
        }
        return soundFileExists(entry.soundFileName) ? entry.soundFileName : nil
    }

    private func soundFileExists(_ fileName: String) -> Bool {
        guard !fileName.isEmpty else { return false }
        let base = fileName.replacingOccurrences(of: ".caf", with: "")
        if Bundle.main.url(forResource: base, withExtension: "caf") != nil {
            return true
        }
        let url = AudioConverter.shared.soundsDirectory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// 再生する音の表示名（プレイリストならプレイリスト名）
    private func soundDisplayName(for entry: AlarmEntry) -> String {
        if entry.playlistID != nil {
            return PlaylistStore.shared.playlist(id: entry.playlistID)?.name
                ?? String(localized: "playlist")
        }
        return SoundStore.shared.displayName(for: entry.soundFileName)
    }

    /// 停止後にシャッフル／1曲ランダムの次回分を作り直す（#151）。
    /// 新しいアラームを登録できてから古い方を消す（登録失敗で鳴らなくならないように）。
    @MainActor
    func reschedulePrimaryAfterStop(entry: AlarmEntry, oldAlarmID: UUID) async {
        guard entry.isEnabled,
              !entry.repeatWeekdays.isEmpty,
              AlarmSoundModeResolver.changesOrderOnStop(for: entry) else {
            return
        }
        let now = Date()
        guard !AlarmSyncSafety.shouldDeferReschedule(for: entry, now: now) else {
            // 発火した分の中では登録し直さない。次の同期で新しい順番を作る（#163）
            var pending = AppGroup.pendingShuffleRefreshEntryIDs
            pending.insert(entry.id)
            AppGroup.pendingShuffleRefreshEntryIDs = pending
            logger.info("Deferred shuffle reschedule during firing minute: \(entry.label)")
            return
        }
        let resolution = await PlaylistRenderService.shared.prepareSound(
            for: entry.playlistRenderInput,
            forceNewOrder: true
        )
        let alarmID = Alarm.ID()
        nonisolated(unsafe) let config = makeAlarmConfiguration(
            for: entry,
            soundFileName: resolution.fileName,
            displayName: soundDisplayName(for: entry),
            alarmID: alarmID
        )
        do {
            _ = try await manager.schedule(id: alarmID, configuration: config)
            try? manager.cancel(id: oldAlarmID)
            alarmIDMap[entry.id] = alarmID
            saveIDMap()
            var names = AppGroup.primarySoundNames
            names[entry.id] = resolution.fileName
            AppGroup.primarySoundNames = names
            // 停止後の作り直しも署名を更新し、次の同期でさらに作り直さない（#163）
            var signatures = AppGroup.primaryAlarmSignatures
            signatures[entry.id] = AlarmScheduleSignature(
                entry: entry,
                soundFileName: resolution.fileName,
                displayName: soundDisplayName(for: entry)
            )
            AppGroup.primaryAlarmSignatures = signatures
            logger.info("Rescheduled playlist alarm for next occurrence: \(entry.label)")
        } catch {
            logger.error("Failed to reschedule playlist alarm \(entry.label): \(error.localizedDescription)")
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
        let displayName = soundDisplayName(for: entry)
        // プレイリストの寝過ごし防止は、存在する最初の曲の「大きくした版」で鳴らす（#151）。
        // 生成できなければ予備音にフォールバックする。
        let source = backupSourceFileName(for: entry) ?? ""
        if !source.isEmpty {
            _ = await BackupLoudVariantService.ensureVariant(for: source)
        }
        let soundFileName = BackupLoudVariantService.resolvedSoundFileName(
            forSourceFileName: source
        )
        var soundNames = AppGroup.backupSoundNames
        soundNames[entry.id] = soundFileName
        AppGroup.backupSoundNames = soundNames
        let config = BackupAlarmFactory.configuration(
            for: entry,
            fireDate: nextDate,
            alarmID: alarmID,
            displayName: displayName,
            soundFileName: soundFileName
        )

        do {
            _ = try await manager.schedule(id: alarmID, configuration: config)
            // 発火前の同期で作り直さないよう、登録した内容の署名を保存する（#163）
            var signatures = AppGroup.backupAlarmSignatures
            signatures[entry.id] = BackupAlarmScheduleSignature(
                entry: entry,
                fireDate: nextDate,
                soundFileName: soundFileName
            )
            AppGroup.backupAlarmSignatures = signatures
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
        var soundNames = AppGroup.backupSoundNames
        for entryID in orphanIDs {
            soundNames.removeValue(forKey: entryID)
        }
        AppGroup.backupSoundNames = soundNames
        saveBackupIDMap()
        logger.info("Cancelled \(orphanIDs.count) orphan backup alarm(s)")
    }

    // MARK: - Test Ring (#109)

    /// 選択中のサウンド（または最終アラーム用の音）で 5 秒後に一度だけ鳴らす。
    /// AlarmStore には保存しない。成功したら ID を AppGroup に記録し、
    /// 停止・60 秒経過・次回起動時でキャンセルする。
    /// 失敗は理由を添えて返し、`test_ring_failed` を記録する（#150）。
    @discardableResult
    func scheduleTestRing(
        soundFileName: String,
        kind: TestRingKind,
        hasBackup: Bool = false,
        now: Date = Date()
    ) async -> TestRingResult {
        refreshTestRingPermission()
        guard canScheduleTestRing else {
            let reason: TestRingFailureReason =
                testRingPermission == .denied ? .denied : .notAuthorized
            logger.warning("Test ring skipped: AlarmKit not authorized (\(reason.rawValue))")
            AnalyticsService.shared.capture(.testRingFailed(reason: reason, kind: kind))
            return .failed(reason)
        }

        #if targetEnvironment(simulator)
        // シミュレータで AlarmKit を鳴らすと SpringBoard が落ちるため登録しない。
        // 鳴動確認は実機で行う（#109）。
        logger.warning("Test ring is disabled on the simulator")
        AnalyticsService.shared.capture(.testRingFailed(reason: .simulator, kind: kind))
        return .failed(.simulator)
        #else
        let plan = TestRingLogic.makePlan(now: now, soundFileName: soundFileName, kind: kind)
        let alarmID = UUID()
        let config = makeTestRingConfiguration(for: plan, alarmID: alarmID)

        do {
            _ = try await manager.schedule(id: alarmID, configuration: config)
            var records = AppGroup.testAlarmRecords
            records.append(TestAlarmRecord(id: alarmID, scheduledAt: now, kind: kind))
            AppGroup.testAlarmRecords = records
            AnalyticsService.shared.capture(.testRingScheduled(kind: kind, hasBackup: hasBackup))
            scheduleTestRingCleanup(for: alarmID)
            logger.info("Scheduled test ring in \(TestRingLogic.delay)s (kind=\(kind.rawValue))")
            return .scheduled
        } catch {
            logger.error("Failed to schedule test ring: \(error.localizedDescription)")
            AnalyticsService.shared.capture(.testRingFailed(reason: .scheduleError, kind: kind))
            return .failed(.scheduleError)
        }
        #endif
    }

    /// 試しアラーム用の AlarmKit 設定（一回限り・スヌーズなし・停止のみ）。
    private nonisolated func makeTestRingConfiguration(
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
                detection: "observer",
                soundMode: AlarmSoundModeResolver.soundMode(for: alarm)
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
    /// そのまま残す entryID → Alarm.ID
    var keptMap: [UUID: Alarm.ID]
    /// 削除/無効化されたためキャンセルが必要な entryID
    var cancelEntryIDs: Set<UUID>
    /// 再スケジュール前にキャンセルすべき旧 Alarm（scheduleEntries のうち oldMap に存在したもの）
    var rescheduleAlarmIDs: [UUID: Alarm.ID]
    /// 新規または変更があったためスケジュールが必要な AlarmEntry
    var scheduleEntries: [AlarmEntry]
    /// 署名が未保存だったため、そのまま残して保存する署名（#163）
    var signatureUpdates: [UUID: AlarmScheduleSignature]
    /// 作り直した理由（entryID → reason・#163）
    var rescheduleReasons: [UUID: AlarmSyncRescheduleReason]
    /// 発火した分の中なので次の同期まで延期した entryID（#163）
    var deferredEntryIDs: Set<UUID>
}

/// 差分同期のための alarmIDMap 遷移を計算する純粋関数。
/// 副作用がなく、単体テスト可能。
///
/// `.scheduled` のアラームは署名が同じなら作り直さない（#163）。
/// 署名が未保存（アップデート直後）なら、そのまま残して現在の署名を保存する。
/// 発火した分（今の分・直前の分）の繰り返しアラームは、作り直しが必要でも延期する。
func computeSyncDiff(
    oldMap: [UUID: Alarm.ID],
    entries: [AlarmEntry],
    activeStates: [Alarm.ID: Alarm.State],
    forceRescheduleEntryIDs: Set<UUID> = [],
    signatures: [UUID: AlarmScheduleSignature] = [:],
    desiredSignatures: [UUID: AlarmScheduleSignature] = [:],
    editedEntryIDs: Set<UUID> = [],
    now: Date = Date(),
    calendar: Calendar = .current
) -> SyncDiff {
    let enabledEntryIDs = Set(entries.filter(\.isEnabled).map(\.id))
    var keptMap: [UUID: Alarm.ID] = [:]
    var cancelEntryIDs = Set<UUID>()
    var rescheduleAlarmIDs: [UUID: Alarm.ID] = [:]
    var scheduleEntries: [AlarmEntry] = []
    var signatureUpdates: [UUID: AlarmScheduleSignature] = [:]
    var rescheduleReasons: [UUID: AlarmSyncRescheduleReason] = [:]
    var deferredEntryIDs = Set<UUID>()

    for entryID in oldMap.keys where !enabledEntryIDs.contains(entryID) {
        cancelEntryIDs.insert(entryID)
    }

    func schedule(_ entry: AlarmEntry, reason: AlarmSyncRescheduleReason) {
        if let oldAlarmID = oldMap[entry.id] {
            rescheduleAlarmIDs[entry.id] = oldAlarmID
        }
        scheduleEntries.append(entry)
        rescheduleReasons[entry.id] = reason
    }

    for entry in entries where entry.isEnabled {
        let oldAlarmID = oldMap[entry.id]
        let state = oldAlarmID.flatMap { activeStates[$0] }
        let isProtected = state == .countdown || state == .alerting || state == .paused

        if let alarmID = oldAlarmID, isProtected {
            // 鳴動中・スヌーズ中は今回の音を優先し、次回の同期で反映する。
            keptMap[entry.id] = alarmID
            continue
        }

        let isForced = forceRescheduleEntryIDs.contains(entry.id)
        let reason: AlarmSyncRescheduleReason
        var needsReschedule = false

        if let alarmID = oldAlarmID, !isForced,
           state == .scheduled,
           let desired = desiredSignatures[entry.id] {
            if let saved = signatures[entry.id] {
                if saved == desired {
                    keptMap[entry.id] = alarmID
                    continue
                }
                reason = .changed
                needsReschedule = true
            } else {
                // 署名が未保存（アップデート直後）は全件を作り直さず、
                // そのまま残して現在の署名を保存する。
                keptMap[entry.id] = alarmID
                signatureUpdates[entry.id] = desired
                continue
            }
        } else if isForced {
            reason = .forced
            needsReschedule = true
        } else if oldAlarmID == nil {
            reason = .missing
            needsReschedule = true
        } else if state == .scheduled, desiredSignatures[entry.id] == nil {
            // 署名を作れない異常時は、既存の登録を維持する。
            keptMap[entry.id] = oldAlarmID!
            continue
        } else {
            // AlarmKit に登録があるが状態が読めない（マップが古い）とき。
            reason = .missing
            needsReschedule = true
        }

        guard needsReschedule else { continue }

        // 延期するのは「AlarmKit に .scheduled で残っていて、署名変更/強制で
        // 作り直したい」場合だけ。AlarmKit に無い（.missing）なら、
        // 次回鳴らなくなる方が困るので延期せずすぐ登録する（#163 レビュー）。
        if state == .scheduled,
           reason == .changed || reason == .forced,
           oldAlarmID != nil,
           AlarmSyncSafety.shouldDeferReschedule(
               for: entry,
               editedEntryIDs: editedEntryIDs,
               now: now,
               calendar: calendar
           ) {
            keptMap[entry.id] = oldAlarmID!
            deferredEntryIDs.insert(entry.id)
            continue
        }

        schedule(entry, reason: reason)
    }

    return SyncDiff(
        keptMap: keptMap,
        cancelEntryIDs: cancelEntryIDs,
        rescheduleAlarmIDs: rescheduleAlarmIDs,
        scheduleEntries: scheduleEntries,
        signatureUpdates: signatureUpdates,
        rescheduleReasons: rescheduleReasons,
        deferredEntryIDs: deferredEntryIDs
    )
}
