import Testing
import Foundation
import AlarmKit
@testable import CustomSoundAlarm

struct SyncDiffTests {

    private func signature(
        _ entry: AlarmEntry,
        sound: String = "PresetMarimba.caf",
        display: String = "Marimba"
    ) -> AlarmScheduleSignature {
        AlarmScheduleSignature(
            entry: entry,
            soundFileName: sound,
            displayName: display
        )
    }

    private func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    // MARK: - All new

    @Test
    func allNewEntries_schedulesAll() {
        let e1 = AlarmEntry(hour: 7, minute: 0)
        let e2 = AlarmEntry(hour: 8, minute: 0)
        let entries = [e1, e2]

        let diff = computeSyncDiff(oldMap: [:], entries: entries, activeStates: [:])

        #expect(diff.keptMap.isEmpty)
        #expect(diff.cancelEntryIDs.isEmpty)
        #expect(diff.scheduleEntries.count == 2)
    }

    // MARK: - All disabled

    @Test
    func allDisabled_cancelsAll() {
        let e = AlarmEntry(id: UUID(), hour: 7, minute: 0, isEnabled: false)
        let alarmID = Alarm.ID()
        let entries = [e]

        let diff = computeSyncDiff(
            oldMap: [e.id: alarmID],
            entries: entries,
            activeStates: [alarmID: .scheduled]
        )

        #expect(diff.keptMap.isEmpty)
        #expect(diff.cancelEntryIDs == [e.id])
        #expect(diff.scheduleEntries.isEmpty)
    }

    // MARK: - Removed (deleted from store)

    @Test
    func removedEntry_cancelled() {
        let entryID = UUID()
        let alarmID = Alarm.ID()

        let diff = computeSyncDiff(
            oldMap: [entryID: alarmID],
            entries: [],
            activeStates: [alarmID: .scheduled]
        )

        #expect(diff.keptMap.isEmpty)
        #expect(diff.cancelEntryIDs == [entryID])
        #expect(diff.scheduleEntries.isEmpty)
    }

    // MARK: - Protected keep (.countdown)

    @Test
    func countdownAlarm_kept() {
        let e = AlarmEntry(hour: 7, minute: 0)
        let alarmID = Alarm.ID()
        let entries = [e]

        let diff = computeSyncDiff(
            oldMap: [e.id: alarmID],
            entries: entries,
            activeStates: [alarmID: .countdown]
        )

        #expect(diff.keptMap == [e.id: alarmID])
        #expect(diff.cancelEntryIDs.isEmpty)
        #expect(diff.scheduleEntries.isEmpty)
    }

    // MARK: - Protected keep (.alerting)

    @Test
    func alertingAlarm_kept() {
        let e = AlarmEntry(hour: 7, minute: 0)
        let alarmID = Alarm.ID()
        let entries = [e]

        let diff = computeSyncDiff(
            oldMap: [e.id: alarmID],
            entries: entries,
            activeStates: [alarmID: .alerting]
        )

        #expect(diff.keptMap == [e.id: alarmID])
        #expect(diff.cancelEntryIDs.isEmpty)
        #expect(diff.scheduleEntries.isEmpty)
    }

    // MARK: - Protected keep (.paused)

    @Test
    func pausedAlarm_kept() {
        let e = AlarmEntry(hour: 7, minute: 0)
        let alarmID = Alarm.ID()
        let entries = [e]

        let diff = computeSyncDiff(
            oldMap: [e.id: alarmID],
            entries: entries,
            activeStates: [alarmID: .paused]
        )

        #expect(diff.keptMap == [e.id: alarmID])
        #expect(diff.cancelEntryIDs.isEmpty)
        #expect(diff.scheduleEntries.isEmpty)
    }

    // MARK: - .scheduled + signature (#163)

    @Test
    func scheduledAlarmWithSameSignature_kept() {
        let e = AlarmEntry(hour: 7, minute: 0)
        let alarmID = Alarm.ID()
        let sig = signature(e)

        let diff = computeSyncDiff(
            oldMap: [e.id: alarmID],
            entries: [e],
            activeStates: [alarmID: .scheduled],
            signatures: [e.id: sig],
            desiredSignatures: [e.id: sig]
        )

        #expect(diff.keptMap == [e.id: alarmID])
        #expect(diff.scheduleEntries.isEmpty)
        #expect(diff.rescheduleReasons.isEmpty)
        #expect(diff.signatureUpdates.isEmpty)
    }

    @Test
    func scheduledAlarmWithChangedSignature_rescheduledAsChanged() {
        let e = AlarmEntry(hour: 7, minute: 0)
        var changed = e
        changed.hour = 8
        let alarmID = Alarm.ID()

        let diff = computeSyncDiff(
            oldMap: [e.id: alarmID],
            entries: [changed],
            activeStates: [alarmID: .scheduled],
            signatures: [e.id: signature(e)],
            desiredSignatures: [e.id: signature(changed)]
        )

        #expect(diff.keptMap.isEmpty)
        #expect(diff.scheduleEntries.map(\.id) == [e.id])
        #expect(diff.rescheduleAlarmIDs[e.id] == alarmID)
        #expect(diff.rescheduleReasons[e.id] == .changed)
    }

    @Test
    func scheduledAlarmWithoutSavedSignature_keptAndAdopts() {
        let e = AlarmEntry(hour: 7, minute: 0)
        let alarmID = Alarm.ID()
        let desired = signature(e)

        let diff = computeSyncDiff(
            oldMap: [e.id: alarmID],
            entries: [e],
            activeStates: [alarmID: .scheduled],
            desiredSignatures: [e.id: desired]
        )

        #expect(diff.keptMap == [e.id: alarmID])
        #expect(diff.scheduleEntries.isEmpty)
        #expect(diff.signatureUpdates[e.id] == desired)
    }

    @Test
    func changedSignatureDuringFiringMinute_deferred() {
        let calendar = fixedCalendar()
        let now = calendar.date(
            from: DateComponents(
                year: 2026, month: 11, day: 4,
                hour: 6, minute: 26, second: 30
            )
        )!
        let e = AlarmEntry(hour: 6, minute: 25, repeatWeekdays: [4])
        var changed = e
        changed.label = "changed"
        let alarmID = Alarm.ID()
        #expect(AlarmSyncSafety.shouldDeferReschedule(
            for: changed,
            now: now,
            calendar: calendar
        ))

        let diff = computeSyncDiff(
            oldMap: [e.id: alarmID],
            entries: [changed],
            activeStates: [alarmID: .scheduled],
            signatures: [e.id: signature(e)],
            desiredSignatures: [e.id: signature(changed)],
            now: now,
            calendar: calendar
        )

        #expect(diff.keptMap == [e.id: alarmID])
        #expect(diff.scheduleEntries.isEmpty)
        #expect(diff.deferredEntryIDs == [e.id])
        #expect(diff.rescheduleReasons.isEmpty)
    }

    @Test
    func editedEntryDuringFiringMinute_isRescheduled() {
        let calendar = fixedCalendar()
        let now = calendar.date(
            from: DateComponents(
                year: 2026, month: 11, day: 4,
                hour: 6, minute: 26, second: 30
            )
        )!
        let e = AlarmEntry(hour: 6, minute: 25, repeatWeekdays: [4])
        var changed = e
        changed.label = "changed"
        let alarmID = Alarm.ID()

        let diff = computeSyncDiff(
            oldMap: [e.id: alarmID],
            entries: [changed],
            activeStates: [alarmID: .scheduled],
            signatures: [e.id: signature(e)],
            desiredSignatures: [e.id: signature(changed)],
            editedEntryIDs: [e.id],
            now: now,
            calendar: calendar
        )

        #expect(diff.keptMap.isEmpty)
        #expect(diff.scheduleEntries.map(\.id) == [e.id])
        #expect(diff.deferredEntryIDs.isEmpty)
        #expect(diff.rescheduleReasons[e.id] == .changed)
    }

    @Test
    func missingEntryDuringFiringMinute_isNotDeferred() {
        let calendar = fixedCalendar()
        let now = calendar.date(
            from: DateComponents(
                year: 2026, month: 11, day: 4,
                hour: 6, minute: 26, second: 30
            )
        )!
        let e = AlarmEntry(hour: 6, minute: 25, repeatWeekdays: [4])
        let staleID = Alarm.ID()
        let sig = signature(e)

        // マップには ID が残っているが AlarmKit には登録が無い（state == nil）
        let diff = computeSyncDiff(
            oldMap: [e.id: staleID],
            entries: [e],
            activeStates: [:],
            signatures: [e.id: sig],
            desiredSignatures: [e.id: sig],
            now: now,
            calendar: calendar
        )

        #expect(diff.keptMap.isEmpty)
        #expect(diff.scheduleEntries.map(\.id) == [e.id])
        #expect(diff.rescheduleReasons[e.id] == .missing)
        #expect(diff.deferredEntryIDs.isEmpty)
    }

    @Test
    func forcedScheduledDuringFiringMinute_isDeferred() {
        let calendar = fixedCalendar()
        let now = calendar.date(
            from: DateComponents(
                year: 2026, month: 11, day: 4,
                hour: 6, minute: 26, second: 30
            )
        )!
        let e = AlarmEntry(hour: 6, minute: 25, repeatWeekdays: [4])
        let alarmID = Alarm.ID()
        let sig = signature(e)

        let diff = computeSyncDiff(
            oldMap: [e.id: alarmID],
            entries: [e],
            activeStates: [alarmID: .scheduled],
            forceRescheduleEntryIDs: [e.id],
            signatures: [e.id: sig],
            desiredSignatures: [e.id: sig],
            now: now,
            calendar: calendar
        )

        #expect(diff.keptMap == [e.id: alarmID])
        #expect(diff.scheduleEntries.isEmpty)
        #expect(diff.deferredEntryIDs == [e.id])
        #expect(diff.rescheduleReasons.isEmpty)
    }

    @Test
    func deferredChangedSignature_retryAfterNinetySeconds_reschedules() {
        let calendar = fixedCalendar()
        let firstAttempt = calendar.date(
            from: DateComponents(
                year: 2026, month: 11, day: 4,
                hour: 6, minute: 26, second: 30
            )
        )!
        let e = AlarmEntry(hour: 6, minute: 25, repeatWeekdays: [4])
        var changed = e
        changed.label = "changed"
        let alarmID = Alarm.ID()
        let oldSignature = signature(e)
        let newSignature = signature(changed)

        let first = computeSyncDiff(
            oldMap: [e.id: alarmID],
            entries: [changed],
            activeStates: [alarmID: .scheduled],
            signatures: [e.id: oldSignature],
            desiredSignatures: [e.id: newSignature],
            now: firstAttempt,
            calendar: calendar
        )
        #expect(first.deferredEntryIDs == [e.id])

        // 90秒後（分が変わった後）の再試行では作り直す
        let retry = computeSyncDiff(
            oldMap: [e.id: alarmID],
            entries: [changed],
            activeStates: [alarmID: .scheduled],
            signatures: [e.id: oldSignature],
            desiredSignatures: [e.id: newSignature],
            now: firstAttempt.addingTimeInterval(90),
            calendar: calendar
        )
        #expect(retry.scheduleEntries.map(\.id) == [e.id])
        #expect(retry.rescheduleReasons[e.id] == .changed)
        #expect(retry.deferredEntryIDs.isEmpty)
    }

    @Test
    func changedSignatureTwoMinutesLater_rescheduled() {
        let calendar = fixedCalendar()
        let now = calendar.date(
            from: DateComponents(
                year: 2026, month: 11, day: 4,
                hour: 6, minute: 27, second: 0
            )
        )!
        let e = AlarmEntry(hour: 6, minute: 25, repeatWeekdays: [4])
        var changed = e
        changed.label = "changed"
        let alarmID = Alarm.ID()

        let diff = computeSyncDiff(
            oldMap: [e.id: alarmID],
            entries: [changed],
            activeStates: [alarmID: .scheduled],
            signatures: [e.id: signature(e)],
            desiredSignatures: [e.id: signature(changed)],
            now: now,
            calendar: calendar
        )

        #expect(diff.scheduleEntries.map(\.id) == [e.id])
        #expect(diff.deferredEntryIDs.isEmpty)
    }

    // MARK: - Protected BUT disabled → cancel

    @Test
    func countdownButDisabled_cancelled() {
        let e = AlarmEntry(id: UUID(), hour: 7, minute: 0, isEnabled: false)
        let alarmID = Alarm.ID()
        let entries = [e]

        let diff = computeSyncDiff(
            oldMap: [e.id: alarmID],
            entries: entries,
            activeStates: [alarmID: .countdown]
        )

        #expect(diff.keptMap.isEmpty)
        #expect(diff.cancelEntryIDs == [e.id])
        #expect(diff.scheduleEntries.isEmpty)
    }

    // MARK: - No active state info for existing mapping

    @Test
    func existingMappingButStateUnknown_rescheduled() {
        let e = AlarmEntry(hour: 7, minute: 0)
        let alarmID = Alarm.ID()
        let entries = [e]

        let diff = computeSyncDiff(
            oldMap: [e.id: alarmID],
            entries: entries,
            activeStates: [:]
        )

        #expect(diff.keptMap.isEmpty)
        #expect(diff.scheduleEntries.count == 1)
        #expect(diff.scheduleEntries[0].id == e.id)
        #expect(diff.rescheduleAlarmIDs.count == 1)
        #expect(diff.rescheduleAlarmIDs[e.id] == alarmID)
    }

    // MARK: - rescheduleAlarmIDs empty for new entries

    @Test
    func rescheduleAlarmIDs_emptyForNewEntry() {
        let e = AlarmEntry(hour: 7, minute: 0)

        let diff = computeSyncDiff(
            oldMap: [:],
            entries: [e],
            activeStates: [:]
        )

        #expect(diff.scheduleEntries.count == 1)
        #expect(diff.rescheduleAlarmIDs.isEmpty)
    }

    // MARK: - Double-sync regression test

    @Test
    func doubleSyncWithSameSignature_doesNotIncreaseAlarmCount() {
        let e = AlarmEntry(hour: 7, minute: 0)
        let firstAlarmID = Alarm.ID()
        let sig = signature(e)

        let diff = computeSyncDiff(
            oldMap: [e.id: firstAlarmID],
            entries: [e],
            activeStates: [firstAlarmID: .scheduled],
            signatures: [e.id: sig],
            desiredSignatures: [e.id: sig]
        )

        // 2回目の同期では作り直さない（同じ分の鳴り直しを防ぐ）
        #expect(diff.keptMap == [e.id: firstAlarmID])
        #expect(diff.scheduleEntries.isEmpty)
        #expect(diff.cancelEntryIDs.isEmpty)
        #expect(diff.rescheduleAlarmIDs.isEmpty)
    }

    // MARK: - Mixed: keep + cancel + schedule

    @Test
    func mixedScenario() {
        let keptEntry = AlarmEntry(hour: 7, minute: 0)
        let keptAlarmID = Alarm.ID()

        let disabledEntry = AlarmEntry(id: UUID(), hour: 8, minute: 0, isEnabled: false)
        let disabledAlarmID = Alarm.ID()

        let newEntry = AlarmEntry(hour: 9, minute: 0)

        let entries = [keptEntry, disabledEntry, newEntry]

        let diff = computeSyncDiff(
            oldMap: [keptEntry.id: keptAlarmID, disabledEntry.id: disabledAlarmID],
            entries: entries,
            activeStates: [keptAlarmID: .countdown, disabledAlarmID: .scheduled]
        )

        #expect(diff.keptMap == [keptEntry.id: keptAlarmID])
        #expect(diff.cancelEntryIDs == [disabledEntry.id])
        #expect(diff.scheduleEntries.count == 1)
        #expect(diff.scheduleEntries[0].id == newEntry.id)
    }

    // MARK: - No overlap: old map entries not in new entries at all

    @Test
    func oldEntryNotInNewEntries_cancelled() {
        let oldEntryID = UUID()
        let oldAlarmID = Alarm.ID()
        let newEntry = AlarmEntry(hour: 9, minute: 0)

        let diff = computeSyncDiff(
            oldMap: [oldEntryID: oldAlarmID],
            entries: [newEntry],
            activeStates: [oldAlarmID: .countdown]
        )

        #expect(diff.keptMap.isEmpty)
        #expect(diff.cancelEntryIDs == [oldEntryID])
        #expect(diff.scheduleEntries.count == 1)
        #expect(diff.scheduleEntries[0].id == newEntry.id)
    }

    // MARK: - Forced reschedule (playlist edit / sound deletion, #160)

    @Test
    func forcedScheduledEntry_rescheduled() {
        let entry = AlarmEntry(hour: 7, minute: 0)
        let alarmID = Alarm.ID()

        let diff = computeSyncDiff(
            oldMap: [entry.id: alarmID],
            entries: [entry],
            activeStates: [alarmID: .scheduled],
            forceRescheduleEntryIDs: [entry.id]
        )

        #expect(diff.keptMap.isEmpty)
        #expect(diff.scheduleEntries.map(\.id) == [entry.id])
        #expect(diff.rescheduleAlarmIDs[entry.id] == alarmID)
        #expect(diff.rescheduleReasons[entry.id] == .forced)
    }

    @Test
    func forcedRingingEntry_staysProtected() {
        let entry = AlarmEntry(hour: 7, minute: 0)
        let alarmID = Alarm.ID()

        let diff = computeSyncDiff(
            oldMap: [entry.id: alarmID],
            entries: [entry],
            activeStates: [alarmID: .alerting],
            forceRescheduleEntryIDs: [entry.id]
        )

        // 鳴動中の音は途切れさせない。次回の同期で新しい書き出しに切り替わる。
        #expect(diff.keptMap == [entry.id: alarmID])
        #expect(diff.scheduleEntries.isEmpty)
    }
}
