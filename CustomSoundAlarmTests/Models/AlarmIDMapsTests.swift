import Testing
import Foundation
@testable import CustomSoundAlarm

struct AlarmIDMapsTests {

    private func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    // MARK: - Stop action table

    @Test
    func stopAction_primaryCancelsBackup() {
        let entryID = uuid(1)
        let primaryID = uuid(10)
        let backupID = uuid(11)

        let action = AlarmIDMaps.stopAction(
            of: primaryID,
            primary: [entryID: primaryID],
            backup: [entryID: backupID]
        )

        #expect(action.role == .primary(entryID: entryID))
        #expect(action.entryID == entryID)
        #expect(action.counterpartAlarmID == backupID)
    }

    @Test
    func stopAction_backupCancelsPrimary() {
        let entryID = uuid(1)
        let primaryID = uuid(10)
        let backupID = uuid(11)

        let action = AlarmIDMaps.stopAction(
            of: backupID,
            primary: [entryID: primaryID],
            backup: [entryID: backupID]
        )

        #expect(action.role == .backup(entryID: entryID))
        #expect(action.counterpartAlarmID == primaryID)
    }

    @Test
    func stopAction_unknownHasNoCounterpart() {
        let entryID = uuid(1)
        let action = AlarmIDMaps.stopAction(
            of: uuid(99),
            primary: [entryID: uuid(10)],
            backup: [entryID: uuid(11)]
        )

        #expect(action.role == .unknown)
        #expect(action.entryID == nil)
        #expect(action.counterpartAlarmID == nil)
    }

    @Test
    func counterpart_returnsBothDirections() {
        let entryID = uuid(1)
        let primaryID = uuid(10)
        let backupID = uuid(11)
        let primary = [entryID: primaryID]
        let backup = [entryID: backupID]

        #expect(AlarmIDMaps.counterpart(of: primaryID, primary: primary, backup: backup) == backupID)
        #expect(AlarmIDMaps.counterpart(of: backupID, primary: primary, backup: backup) == primaryID)
    }

    @Test
    func stopAction_primaryWithoutBackupHasNoCounterpart() {
        let entryID = uuid(1)
        let primaryID = uuid(10)
        let action = AlarmIDMaps.stopAction(
            of: primaryID,
            primary: [entryID: primaryID],
            backup: [:]
        )
        #expect(action.role == .primary(entryID: entryID))
        #expect(action.counterpartAlarmID == nil)
    }

    // MARK: - Persistence

    @Test
    func maps_roundTripThroughAppGroup() {
        let originalPrimary = AlarmIDMaps.loadPrimary()
        let originalBackup = AlarmIDMaps.loadBackup()
        defer {
            AlarmIDMaps.savePrimary(originalPrimary)
            AlarmIDMaps.saveBackup(originalBackup)
        }

        let entryID = uuid(1)
        let primaryID = uuid(10)
        let backupID = uuid(11)

        AlarmIDMaps.savePrimary([entryID: primaryID])
        AlarmIDMaps.saveBackup([entryID: backupID])

        #expect(AlarmIDMaps.loadPrimary() == [entryID: primaryID])
        #expect(AlarmIDMaps.loadBackup() == [entryID: backupID])
    }
}
