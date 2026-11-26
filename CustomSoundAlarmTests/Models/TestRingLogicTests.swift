import Testing
import Foundation
@testable import CustomSoundAlarm

struct TestRingLogicTests {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Plan

    @Test
    func makePlan_firesInOneSecond() {
        let plan = TestRingLogic.makePlan(now: base, soundFileName: "PresetBeep.caf", kind: .own)

        #expect(plan.fireDate == base.addingTimeInterval(1))
        #expect(plan.soundFileName == "PresetBeep.caf")
        #expect(plan.kind == .own)
    }

    @Test
    func delayIsOneSecond() {
        #expect(TestRingLogic.delay == 1)
    }

    @Test
    func makePlan_isOneShotWithoutSnooze() {
        let plan = TestRingLogic.makePlan(now: base, soundFileName: "", kind: .backup)

        #expect(plan.repeatsNever)
        #expect(plan.snoozeMinutes == 0)
        #expect(plan.kind == .backup)
    }

    // MARK: - Cleanup

    @Test
    func cleanup_keepsRecordBeforeSixtySeconds() {
        let record = TestAlarmRecord(id: UUID(), scheduledAt: base, kind: .own)

        let result = TestRingLogic.cleanup(
            records: [record],
            now: base.addingTimeInterval(59.9)
        )

        #expect(result.remaining == [record])
        #expect(result.expiredIDs.isEmpty)
    }

    @Test
    func cleanup_expiresRecordAtSixtySeconds() {
        let record = TestAlarmRecord(id: UUID(), scheduledAt: base, kind: .own)

        let result = TestRingLogic.cleanup(
            records: [record],
            now: base.addingTimeInterval(60)
        )

        #expect(result.remaining.isEmpty)
        #expect(result.expiredIDs == [record.id])
    }

    @Test
    func cleanup_mixedRecords_expiresOnlyOldOnes() {
        let old = TestAlarmRecord(id: UUID(), scheduledAt: base, kind: .own)
        let recent = TestAlarmRecord(id: UUID(), scheduledAt: base.addingTimeInterval(30), kind: .backup)

        let result = TestRingLogic.cleanup(
            records: [old, recent],
            now: base.addingTimeInterval(61)
        )

        #expect(result.remaining == [recent])
        #expect(result.expiredIDs == [old.id])
    }

    /// 陰性確認の対象: 掃除を外すとこのテストが落ちる（PR に記載）。
    /// App Group に記録した試しアラームが 60 秒後に空になることを、実際の記録経路で検証する。
    @Test
    func appGroupRecords_areEmptyAfterSixtySeconds() {
        let original = AppGroup.testAlarmRecords
        defer { AppGroup.testAlarmRecords = original }

        let record = TestAlarmRecord(id: UUID(), scheduledAt: base, kind: .own)
        AppGroup.testAlarmRecords = [record]
        #expect(AppGroup.testAlarmIDs == [record.id])

        let result = TestRingLogic.cleanup(
            records: AppGroup.testAlarmRecords,
            now: base.addingTimeInterval(61)
        )
        AppGroup.testAlarmRecords = result.remaining

        #expect(AppGroup.testAlarmIDs.isEmpty)
    }

    // MARK: - Stop classification

    @Test
    func isTestStop_whenTestAlarmIsAlerting() {
        let record = TestAlarmRecord(id: UUID(), scheduledAt: base, kind: .own)

        #expect(TestRingLogic.isTestStop(
            activeIDs: [record.id],
            alertingIDs: [record.id],
            records: [record],
            now: base.addingTimeInterval(5)
        ))
    }

    @Test
    func isTestStop_whenProductionAlarmIsAlerting() {
        let testRecord = TestAlarmRecord(id: UUID(), scheduledAt: base, kind: .own)
        let productionID = UUID()

        // 試しの記録が残っていても、鳴っているのが本番アラームなら本番の停止として扱う
        #expect(!TestRingLogic.isTestStop(
            activeIDs: [productionID, testRecord.id],
            alertingIDs: [productionID],
            records: [testRecord],
            now: base.addingTimeInterval(20)
        ))
    }

    @Test
    func isTestStop_whenTestAlarmIsStillActiveButNotAlerting() {
        let record = TestAlarmRecord(id: UUID(), scheduledAt: base, kind: .backup)

        #expect(TestRingLogic.isTestStop(
            activeIDs: [record.id],
            alertingIDs: [],
            records: [record],
            now: base.addingTimeInterval(3)
        ))
    }

    @Test
    func isTestStop_whenAlarmAlreadyGoneButRecordIsRecent() {
        let record = TestAlarmRecord(id: UUID(), scheduledAt: base, kind: .own)

        #expect(TestRingLogic.isTestStop(
            activeIDs: [],
            alertingIDs: [],
            records: [record],
            now: base.addingTimeInterval(90)
        ))
    }

    @Test
    func isTestStop_whenRecordIsStale() {
        let record = TestAlarmRecord(id: UUID(), scheduledAt: base, kind: .own)

        #expect(!TestRingLogic.isTestStop(
            activeIDs: [],
            alertingIDs: [],
            records: [record],
            now: base.addingTimeInterval(TestRingLogic.recentWindow + 1)
        ))
    }

    @Test
    func isTestStop_whenNoRecords() {
        #expect(!TestRingLogic.isTestStop(
            activeIDs: [UUID()],
            alertingIDs: [UUID()],
            records: [],
            now: base
        ))
    }

    // MARK: - performSync protection

    /// `performSync` は alarmIDMap に載っている ID だけをキャンセルする。
    /// 試しアラームは alarmIDMap に載せないため、同期で消されない（現状の作りを固定）。
    @Test
    func syncDiff_doesNotCancelTestAlarm() {
        let entry = AlarmEntry(hour: 7, minute: 0)
        let productionID = UUID()
        let testRecord = TestAlarmRecord(id: UUID(), scheduledAt: base, kind: .own)

        let diff = computeSyncDiff(
            oldMap: [entry.id: productionID],
            entries: [entry],
            activeStates: [productionID: .scheduled]
        )

        #expect(diff.cancelEntryIDs.isEmpty)
        #expect(!diff.cancelEntryIDs.contains(testRecord.id))
    }

    // MARK: - Wait bucket (#310)

    @Test
    func waitBucket_boundaries() {
        #expect(TestRingLogic.waitBucket(seconds: 0) == .under2)
        #expect(TestRingLogic.waitBucket(seconds: 1.99) == .under2)
        #expect(TestRingLogic.waitBucket(seconds: 2) == .twoToFour)
        #expect(TestRingLogic.waitBucket(seconds: 3.99) == .twoToFour)
        #expect(TestRingLogic.waitBucket(seconds: 4) == .fourToSeven)
        #expect(TestRingLogic.waitBucket(seconds: 6.99) == .fourToSeven)
        #expect(TestRingLogic.waitBucket(seconds: 7) == .sevenToFifteen)
        #expect(TestRingLogic.waitBucket(seconds: 14.99) == .sevenToFifteen)
        #expect(TestRingLogic.waitBucket(seconds: 15) == .fifteenPlus)
        #expect(TestRingLogic.waitBucket(seconds: 300) == .fifteenPlus)
    }

    @Test
    func waitBucket_rawValuesAreStableAnalyticsIdentifiers() {
        #expect(TestRingLogic.WaitBucket.under2.rawValue == "<2")
        #expect(TestRingLogic.WaitBucket.twoToFour.rawValue == "2-4")
        #expect(TestRingLogic.WaitBucket.fourToSeven.rawValue == "4-7")
        #expect(TestRingLogic.WaitBucket.sevenToFifteen.rawValue == "7-15")
        #expect(TestRingLogic.WaitBucket.fifteenPlus.rawValue == "15+")
    }

    // MARK: - Button state (#310)

    @Test
    func buttonState_idleToWaitingToRingingToIdle() {
        let waiting = TestRingLogic.next(state: .idle, event: .press)
        #expect(waiting == .waiting)
        #expect(!waiting.isEnabled)
        #expect(waiting.wigglesIcon)

        let ringing = TestRingLogic.next(state: waiting, event: .alerting)
        #expect(ringing == .ringing)
        #expect(!ringing.isEnabled)
        #expect(!ringing.wigglesIcon, "鳴っている間は揺らさない")

        #expect(TestRingLogic.next(state: ringing, event: .disappeared) == .idle)
    }

    @Test
    func buttonState_timeoutReturnsToIdleOnlyWhileWaiting() {
        #expect(TestRingLogic.next(state: .waiting, event: .timeout) == .idle)
        // 鳴っている間の 60 秒では止めない
        #expect(TestRingLogic.next(state: .ringing, event: .timeout) == .ringing)
    }

    @Test
    func buttonState_failureReturnsToIdle() {
        #expect(TestRingLogic.next(state: .waiting, event: .failed) == .idle)
    }

    @Test
    func buttonState_disappearedWhileWaitingReturnsToIdle() {
        #expect(TestRingLogic.next(state: .waiting, event: .disappeared) == .idle)
    }

    @Test
    func buttonState_idleIgnoresUnexpectedEvents() {
        #expect(TestRingLogic.next(state: .idle, event: .alerting) == .idle)
        #expect(TestRingLogic.next(state: .idle, event: .disappeared) == .idle)
        #expect(TestRingLogic.next(state: .idle, event: .timeout) == .idle)
        #expect(TestRingLogic.next(state: .idle, event: .failed) == .idle)
    }

    @Test
    func buttonState_titlesAndFlags() {
        #expect(TestRingLogic.ButtonState.idle.titleKey == "test_ring_title")
        #expect(TestRingLogic.ButtonState.waiting.titleKey == "test_ring_waiting")
        #expect(TestRingLogic.ButtonState.ringing.titleKey == "test_ring_ringing")
        #expect(TestRingLogic.ButtonState.idle.isEnabled)
        #expect(TestRingLogic.ButtonState.idle.wigglesIcon == false)
    }
}
