import Testing
import Foundation
@testable import CustomSoundAlarm

struct PlaylistApplyLogicTests {

    @Test
    func onlySelectedAlarmsAreChangedToThePlaylist() {
        let selected = UUID()
        let untouched = UUID()
        let playlistID = UUID()
        let alarms = [
            AlarmEntry(id: selected, hour: 6, minute: 30, soundFileName: "old.caf"),
            AlarmEntry(id: untouched, hour: 7, minute: 0, soundFileName: "keep.caf")
        ]

        let updated = PlaylistApplyLogic.appliedAlarms(
            alarms,
            selectedIDs: [selected],
            playlistID: playlistID
        )

        #expect(updated[0].playlistID == playlistID)
        #expect(updated[0].soundFileName.isEmpty)
        #expect(updated[1].playlistID == nil)
        #expect(updated[1].soundFileName == "keep.caf")
    }

    @Test
    func noSelectionLeavesEveryAlarmUnchanged() {
        let alarms = [
            AlarmEntry(hour: 6, minute: 30, soundFileName: "old.caf"),
            AlarmEntry(hour: 7, minute: 0, soundFileName: "keep.caf")
        ]

        let updated = PlaylistApplyLogic.appliedAlarms(
            alarms,
            selectedIDs: [],
            playlistID: UUID()
        )

        #expect(updated == alarms)
    }

    @Test
    func zeroAlarmsOpensTheAddScreen() {
        #expect(PlaylistApplyLogic.shouldOpenAddAlarm(alarmCount: 0))
        #expect(!PlaylistApplyLogic.shouldOpenAddAlarm(alarmCount: 1))
    }

    @Test
    func alarmCountBucketsMatchTheDocumentedRanges() {
        #expect(PlaylistApplyAlarmCountBucket(count: 0) == .zero)
        #expect(PlaylistApplyAlarmCountBucket(count: 1) == .one)
        #expect(PlaylistApplyAlarmCountBucket(count: 2) == .twoToThree)
        #expect(PlaylistApplyAlarmCountBucket(count: 3) == .twoToThree)
        #expect(PlaylistApplyAlarmCountBucket(count: 4) == .fourToNine)
        #expect(PlaylistApplyAlarmCountBucket(count: 9) == .fourToNine)
        #expect(PlaylistApplyAlarmCountBucket(count: 10) == .tenPlus)
        #expect(PlaylistApplyAlarmCountBucket(count: 99) == .tenPlus)
    }
}
