import Testing
import Foundation
import AlarmKit
@testable import CustomSoundAlarm

struct SyncDiffTests {

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

    // MARK: - .scheduled → reschedule

    @Test
    func scheduledAlarm_rescheduled() {
        let e = AlarmEntry(hour: 7, minute: 0)
        let alarmID = Alarm.ID()
        let entries = [e]

        let diff = computeSyncDiff(
            oldMap: [e.id: alarmID],
            entries: entries,
            activeStates: [alarmID: .scheduled]
        )

        #expect(diff.keptMap.isEmpty)
        #expect(diff.scheduleEntries.count == 1)
        #expect(diff.scheduleEntries[0].id == e.id)
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
}
