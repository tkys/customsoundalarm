import Testing
import Foundation
@testable import CustomSoundAlarm

/// 初めての1回きりアラームの提案（#247）。
struct FirstAlarmFollowupLogicTests {

    private let alarmID = UUID()

    private func line(
        _ event: String,
        uid: String,
        repeatDays: String = "",
        isRepeating: Bool? = nil
    ) -> String {
        var properties: [String: Any] = [
            "alarm_uid": uid,
            "alarm_time": "07:00",
            "repeat_days": repeatDays
        ]
        properties["is_repeating"] = isRepeating
        let data = try! JSONSerialization.data(withJSONObject: [
            "event": event,
            "properties": properties
        ], options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func candidate(_ lines: [String], alarms: [AlarmEntry]? = nil) -> UUID? {
        let entries = alarms ?? [AlarmEntry(id: alarmID, hour: 7, minute: 0)]
        return FirstAlarmFollowupLogic.candidateAlarmID(
            historyLines: lines,
            alarms: entries,
            uidForAlarm: { _ in "uid-1" }
        )
    }

    @Test
    func firstOneTimeAlarmThatFiredAndStoppedIsReturned() {
        let lines = [
            line("alarm_fired", uid: "uid-1"),
            line("alarm_stopped", uid: "uid-1")
        ]
        #expect(candidate(lines) == alarmID)
    }

    @Test
    func repeatingAlarmIsIgnored() {
        let lines = [
            line("alarm_fired", uid: "uid-1", repeatDays: "2,3,4,5,6", isRepeating: true),
            line("alarm_stopped", uid: "uid-1", repeatDays: "2,3,4,5,6")
        ]
        #expect(candidate(lines) == nil)
    }

    @Test
    func stoppedWithoutFiredIsIgnored() {
        #expect(candidate([line("alarm_stopped", uid: "uid-1")]) == nil)
    }

    @Test
    func onlyTheFirstCompletedOneTimeAlarmIsReturned() {
        let secondID = UUID()
        let alarms = [
            AlarmEntry(id: alarmID, hour: 7, minute: 0),
            AlarmEntry(id: secondID, hour: 8, minute: 0)
        ]
        let lines = [
            line("alarm_fired", uid: "uid-2"),
            line("alarm_stopped", uid: "uid-2"),
            line("alarm_fired", uid: "uid-1"),
            line("alarm_stopped", uid: "uid-1")
        ]
        // 先に完了した uid-2 のアラームが返る
        let result = FirstAlarmFollowupLogic.candidateAlarmID(
            historyLines: lines,
            alarms: alarms,
            uidForAlarm: { $0 == self.alarmID ? "uid-1" : "uid-2" }
        )
        #expect(result == secondID)
    }

    @Test
    func deletedAlarmIsNotProposed() {
        let other = AlarmEntry(id: UUID(), hour: 8, minute: 0)
        let result = FirstAlarmFollowupLogic.candidateAlarmID(
            historyLines: [
                line("alarm_fired", uid: "uid-1"),
                line("alarm_stopped", uid: "uid-1")
            ],
            alarms: [other],
            uidForAlarm: { _ in "other-uid" }
        )
        #expect(result == nil)
    }

    @Test
    func tomorrowKeepsOneTimeAndTurnsOn() throws {
        let alarm = AlarmEntry(hour: 7, minute: 0, isEnabled: false, repeatWeekdays: [1, 7])
        let updated = try #require(FirstAlarmFollowupLogic.updatedAlarm(alarm, for: .tomorrow))
        #expect(updated.isEnabled)
        #expect(updated.repeatWeekdays.isEmpty)
        #expect(updated.hour == 7)
    }

    @Test
    func weekdaysTurnsOnMondayToFriday() throws {
        let alarm = AlarmEntry(hour: 7, minute: 0, isEnabled: false)
        let updated = try #require(FirstAlarmFollowupLogic.updatedAlarm(alarm, for: .weekdays))
        #expect(updated.isEnabled)
        #expect(updated.repeatWeekdays == [2, 3, 4, 5, 6])
    }

    @Test
    func everydayTurnsOnAllDays() throws {
        let alarm = AlarmEntry(hour: 7, minute: 0, isEnabled: false)
        let updated = try #require(FirstAlarmFollowupLogic.updatedAlarm(alarm, for: .everyday))
        #expect(updated.isEnabled)
        #expect(updated.repeatWeekdays == [1, 2, 3, 4, 5, 6, 7])
    }

    @Test
    func ignoredDoesNotChangeTheAlarm() {
        let alarm = AlarmEntry(hour: 7, minute: 0, isEnabled: false)
        #expect(FirstAlarmFollowupLogic.updatedAlarm(alarm, for: .ignored) == nil)
    }

    @Test
    func onlyOneSuggestionPerOpen() {
        #expect(!FirstAlarmFollowupLogic.shouldShow(
            hasPermissionBanner: true,
            unlockWouldShow: true
        ))
        #expect(!FirstAlarmFollowupLogic.shouldShow(
            hasPermissionBanner: true,
            unlockWouldShow: false
        ))
        #expect(!FirstAlarmFollowupLogic.shouldShow(
            hasPermissionBanner: false,
            unlockWouldShow: true
        ))
        #expect(FirstAlarmFollowupLogic.shouldShow(
            hasPermissionBanner: false,
            unlockWouldShow: false
        ))
    }

    @Test
    func analyticsActionsAreStable() {
        #expect(FirstAlarmFollowupAction.tomorrow.rawValue == "tomorrow")
        #expect(FirstAlarmFollowupAction.weekdays.rawValue == "weekdays")
        #expect(FirstAlarmFollowupAction.everyday.rawValue == "everyday")
        #expect(FirstAlarmFollowupAction.ignored.rawValue == "ignored")
        #expect(AnalyticsEvent.firstAlarmFollowupShown.name == "first_alarm_followup_shown")
        #expect(
            AnalyticsEvent.firstAlarmFollowupAction(action: .ignored)
                .properties["action"] as? String == "ignored"
        )
    }
}
