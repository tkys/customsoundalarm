import Testing
import Foundation
@testable import CustomSoundAlarm

/// 初めての1回きりアラームの提案（#247）。
struct FirstAlarmFollowupLogicTests {

    private let alarmID = UUID()
    private let defaultTS = "2026-11-19T07:00:00+09:00"
    /// defaultTS の1時間後。実行日に左右されないよう「今」を固定する。
    private var defaultNow: Date {
        ISO8601DateFormatter().date(from: defaultTS)!.addingTimeInterval(3600)
    }

    private func line(
        _ event: String,
        uid: String,
        repeatDays: String = "",
        isRepeating: Bool? = nil,
        ts: String? = nil
    ) -> String {
        var properties: [String: Any] = [
            "alarm_uid": uid,
            "alarm_time": "07:00",
            "repeat_days": repeatDays
        ]
        properties["is_repeating"] = isRepeating
        let data = try! JSONSerialization.data(withJSONObject: [
            "event": event,
            "ts": ts ?? defaultTS,
            "properties": properties
        ], options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func candidate(_ lines: [String], alarms: [AlarmEntry]? = nil) -> UUID? {
        let entries = alarms ?? [AlarmEntry(id: alarmID, hour: 7, minute: 0)]
        return FirstAlarmFollowupLogic.candidate(
            historyLines: lines,
            alarms: entries,
            uidForAlarm: { _ in "uid-1" }
        )?.alarmID
    }

    private func eligibility(
        _ lines: [String],
        alarms: [AlarmEntry]? = nil,
        now: Date? = nil
    ) -> FirstAlarmFollowupEligibility {
        let entries = alarms ?? [
            AlarmEntry(id: alarmID, hour: 7, minute: 0, isEnabled: false)
        ]
        let candidate = FirstAlarmFollowupLogic.candidate(
            historyLines: lines,
            alarms: entries,
            uidForAlarm: { _ in "uid-1" }
        )
        return FirstAlarmFollowupLogic.eligibility(
            candidate: candidate,
            alarms: entries,
            now: now ?? defaultNow
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

    // MARK: - 鳴った記録の有無（#324）

    @Test
    func hasFiredAlarmIsTrueWhenAnyFiredEventExists() {
        #expect(FirstAlarmFollowupLogic.hasFiredAlarm(historyLines: [
            line("alarm_stopped", uid: "uid-1"),
            line("alarm_fired", uid: "uid-1")
        ]))
    }

    @Test
    func hasFiredAlarmIsFalseWithoutFiredEvent() {
        #expect(!FirstAlarmFollowupLogic.hasFiredAlarm(historyLines: [
            line("alarm_stopped", uid: "uid-1"),
            line("alarm_snoozed", uid: "uid-1")
        ]))
        #expect(!FirstAlarmFollowupLogic.hasFiredAlarm(historyLines: []))
        #expect(!FirstAlarmFollowupLogic.hasFiredAlarm(historyLines: ["not json"]))
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
    func firstFiredRepeatingMakesThePersonIneligible() {
        // 最初に鳴ったのが繰り返しなら、あとから1回きりが鳴っても対象外（#247 レビュー）
        let lines = [
            line("alarm_fired", uid: "uid-repeat", repeatDays: "2", isRepeating: true),
            line("alarm_stopped", uid: "uid-repeat", repeatDays: "2"),
            line("alarm_fired", uid: "uid-once"),
            line("alarm_stopped", uid: "uid-once")
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
        let result = FirstAlarmFollowupLogic.candidate(
            historyLines: lines,
            alarms: alarms,
            uidForAlarm: { $0 == self.alarmID ? "uid-1" : "uid-2" }
        )
        #expect(result?.alarmID == secondID)
    }

    @Test
    func deletedAlarmIsNotOffered() {
        let other = AlarmEntry(id: UUID(), hour: 8, minute: 0, isEnabled: false)
        let lines = [
            line("alarm_fired", uid: "uid-1"),
            line("alarm_stopped", uid: "uid-1")
        ]
        let result = FirstAlarmFollowupLogic.candidate(
            historyLines: lines,
            alarms: [other],
            uidForAlarm: { _ in "other-uid" }
        )
        #expect(result?.alarmID == nil)
        #expect(FirstAlarmFollowupLogic.eligibility(
            candidate: result,
            alarms: [other],
            now: defaultNow
        ) == .changedOrRemoved)
    }

    @Test
    func versionBefore183IsIneligible() {
        #expect(!FirstAlarmFollowupLogic.isFirstInstallVersionEligible("1.8.2"))
        #expect(!FirstAlarmFollowupLogic.isFirstInstallVersionEligible("1.8"))
        #expect(!FirstAlarmFollowupLogic.isFirstInstallVersionEligible(nil))
        #expect(FirstAlarmFollowupLogic.isFirstInstallVersionEligible("1.8.3"))
        // 数値として比較する（1.8.10 は 1.8.3 より新しい）
        #expect(FirstAlarmFollowupLogic.isFirstInstallVersionEligible("1.8.10"))
        #expect(FirstAlarmFollowupLogic.isFirstInstallVersionEligible("1.9"))
    }

    @Test
    func alarmChangedToOnOrRepeatingIsNotOffered() {
        let lines = [
            line("alarm_fired", uid: "uid-1"),
            line("alarm_stopped", uid: "uid-1")
        ]
        let now = defaultNow
        #expect(eligibility(
            lines,
            alarms: [AlarmEntry(id: alarmID, hour: 7, minute: 0, isEnabled: true)],
            now: now
        ) == .changedOrRemoved)
        #expect(eligibility(
            lines,
            alarms: [AlarmEntry(
                id: alarmID,
                hour: 7,
                minute: 0,
                isEnabled: false,
                repeatWeekdays: [2, 3]
            )],
            now: now
        ) == .changedOrRemoved)
        #expect(eligibility(
            lines,
            alarms: [AlarmEntry(id: alarmID, hour: 7, minute: 0, isEnabled: false)],
            now: now
        ) == .offer(alarmID))
    }

    @Test
    func stoppedFourDaysAgoIsTooOld() {
        let now = ISO8601DateFormatter().date(from: "2026-11-19T09:00:00Z")!
        let lines = [
            line("alarm_fired", uid: "uid-1", ts: "2026-11-10T07:00:00Z"),
            line("alarm_stopped", uid: "uid-1", ts: "2026-11-15T07:00:00Z")
        ]
        #expect(eligibility(lines, now: now) == .tooOld)

        let recent = [
            line("alarm_fired", uid: "uid-1", ts: "2026-11-18T07:00:00Z"),
            line("alarm_stopped", uid: "uid-1", ts: "2026-11-18T07:00:00Z")
        ]
        #expect(eligibility(recent, now: now) == .offer(alarmID))
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
