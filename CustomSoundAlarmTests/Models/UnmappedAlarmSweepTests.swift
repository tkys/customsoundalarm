import Testing
import Foundation
import AlarmKit
@testable import CustomSoundAlarm

struct UnmappedAlarmSweepTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func shouldSweep_launchWithoutRecentStop() {
        #expect(UnmappedAlarmSweep.shouldSweep(trigger: .launch, now: now, lastStopIntentAt: nil))
        #expect(UnmappedAlarmSweep.shouldSweep(trigger: .foreground, now: now, lastStopIntentAt: now.addingTimeInterval(-301)))
        #expect(UnmappedAlarmSweep.shouldSweep(trigger: .edit, now: now, lastStopIntentAt: now.addingTimeInterval(-3600)))
    }

    @Test
    func shouldSweep_neverForIntent() {
        #expect(!UnmappedAlarmSweep.shouldSweep(trigger: .intent, now: now, lastStopIntentAt: nil))
    }

    @Test
    func shouldSweep_notWithinFiveMinutesOfStop() {
        #expect(!UnmappedAlarmSweep.shouldSweep(trigger: .foreground, now: now, lastStopIntentAt: now))
        #expect(!UnmappedAlarmSweep.shouldSweep(trigger: .foreground, now: now, lastStopIntentAt: now.addingTimeInterval(-299)))
    }

    @Test
    func shouldSweep_notWhenClockMovedBackwards() {
        #expect(!UnmappedAlarmSweep.shouldSweep(trigger: .launch, now: now, lastStopIntentAt: now.addingTimeInterval(600)))
    }

    @Test
    func orphanIDs_onlyUnknownScheduled() {
        let known = UUID()
        let orphan = UUID()
        let ringing = UUID()
        let snoozed = UUID()
        let paused = UUID()
        let snapshots = [
            AlarmSnapshot(id: known, state: .scheduled),
            AlarmSnapshot(id: orphan, state: .scheduled),
            AlarmSnapshot(id: ringing, state: .alerting),
            AlarmSnapshot(id: snoozed, state: .countdown),
            AlarmSnapshot(id: paused, state: .paused),
        ]
        #expect(UnmappedAlarmSweep.orphanIDs(snapshots: snapshots, knownIDs: [known]) == [orphan])
    }

    @Test
    func orphanIDs_emptyWhenAllKnown() {
        let a = UUID(), b = UUID()
        let snapshots = [AlarmSnapshot(id: a, state: .scheduled), AlarmSnapshot(id: b, state: .scheduled)]
        #expect(UnmappedAlarmSweep.orphanIDs(snapshots: snapshots, knownIDs: [a, b]).isEmpty)
    }
}
