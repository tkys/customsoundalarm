import Testing
import Foundation
import AlarmKit
@testable import CustomSoundAlarm

struct StopActionPlannerTests {

    private func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    private let entryID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let primaryID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
    private let backupID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!

    private var primary: [UUID: UUID] { [entryID: primaryID] }
    private var backup: [UUID: UUID] { [entryID: backupID] }

    // MARK: - 最終アラームを止めたとき

    @Test
    func backupStop_doesNotCancelPrimary() {
        let actions = StopActionPlanner.plan(
            stoppedAlarmID: backupID,
            primary: primary,
            backup: backup,
            primaryState: .countdown,
            hasNextBackup: true
        )

        // 繰り返しを消す cancel は絶対に出さない
        #expect(!actions.contains(.cancel(alarmID: primaryID)))
        // スヌーズ中だけ stop する
        #expect(actions.contains(.stop(alarmID: primaryID)))
        // 次回分を登録する
        #expect(actions.contains(.scheduleNextBackup(entryID: entryID)))
    }

    @Test
    func backupStop_whenPrimaryIsAlerting_onlySchedulesNext() {
        let actions = StopActionPlanner.plan(
            stoppedAlarmID: backupID,
            primary: primary,
            backup: backup,
            primaryState: .alerting,
            hasNextBackup: true
        )

        #expect(actions == [.scheduleNextBackup(entryID: entryID)])
    }

    @Test
    func backupStop_oneTime_onlyStopsAndDoesNotScheduleNext() {
        let actions = StopActionPlanner.plan(
            stoppedAlarmID: backupID,
            primary: primary,
            backup: backup,
            primaryState: .countdown,
            hasNextBackup: false
        )

        #expect(actions == [.stop(alarmID: primaryID)])
    }

    // MARK: - 本体を止めたとき

    @Test
    func primaryStop_cancelsBackupAndSchedulesNext() {
        let actions = StopActionPlanner.plan(
            stoppedAlarmID: primaryID,
            primary: primary,
            backup: backup,
            primaryState: .alerting,
            hasNextBackup: true
        )

        #expect(actions.contains(.cancel(alarmID: backupID)))
        #expect(actions.contains(.scheduleNextBackup(entryID: entryID)))
        #expect(!actions.contains(.stop(alarmID: primaryID)))
    }

    @Test
    func primaryStop_oneTime_onlyCancelsBackup() {
        let actions = StopActionPlanner.plan(
            stoppedAlarmID: primaryID,
            primary: primary,
            backup: backup,
            primaryState: .alerting,
            hasNextBackup: false
        )

        #expect(actions == [.cancel(alarmID: backupID)])
    }

    // MARK: - その他

    @Test
    func unknownAlarm_hasNoActions() {
        let actions = StopActionPlanner.plan(
            stoppedAlarmID: uuid(99),
            primary: primary,
            backup: backup,
            primaryState: nil,
            hasNextBackup: true
        )
        #expect(actions.isEmpty)
    }
}
