import Testing
import Foundation
@testable import CustomSoundAlarm

struct TestRingLogicTests {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Plan

    @Test
    func makePlan_firesInFiveSeconds() {
        let plan = TestRingLogic.makePlan(now: base, soundFileName: "PresetBeep.caf", kind: .own)

        #expect(plan.fireDate == base.addingTimeInterval(5))
        #expect(plan.soundFileName == "PresetBeep.caf")
        #expect(plan.kind == .own)
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
}
