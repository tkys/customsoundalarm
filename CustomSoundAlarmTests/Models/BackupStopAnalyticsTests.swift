import Testing
import Foundation
@testable import CustomSoundAlarm

struct BackupStopAnalyticsTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let entryID = UUID()

    @Test
    func backupStop_createsPendingEvent() {
        let entry = AlarmEntry(id: entryID, backupMinutes: 15)

        let event = BackupStopAnalytics.pendingEvent(
            role: .backup(entryID: entryID),
            entry: entry,
            snoozesBefore: 2,
            hour: 7,
            timestamp: now
        )

        let pending = try? #require(event)
        #expect(pending?.name == "backup_alarm_stopped")
        #expect(pending?.hour == 7)
        #expect(pending?.intProperties?["minutes"] == 15)
        #expect(pending?.intProperties?["snoozes_before"] == 2)
        #expect(pending?.postHogProperties["minutes"] as? Int == 15)
        #expect(pending?.postHogProperties["snoozes_before"] as? Int == 2)
        #expect(pending?.postHogProperties["hour"] as? Int == 7)
    }

    @Test
    func primaryStop_doesNotCreateEvent() {
        let entry = AlarmEntry(id: entryID, backupMinutes: 15)
        #expect(BackupStopAnalytics.pendingEvent(
            role: .primary(entryID: entryID),
            entry: entry,
            snoozesBefore: 2,
            hour: 7,
            timestamp: now
        ) == nil)
    }

    @Test
    func unknownRole_doesNotCreateEvent() {
        #expect(BackupStopAnalytics.pendingEvent(
            role: .unknown,
            entry: nil,
            snoozesBefore: nil,
            hour: 7,
            timestamp: now
        ) == nil)
    }

    @Test
    func backupWithoutMinutes_doesNotCreateEvent() {
        let entry = AlarmEntry(id: entryID, backupMinutes: nil)
        #expect(BackupStopAnalytics.pendingEvent(
            role: .backup(entryID: entryID),
            entry: entry,
            snoozesBefore: 1,
            hour: 7,
            timestamp: now
        ) == nil)
    }

    @Test
    func backupStop_withoutSnoozes_omitsSnoozesBefore() {
        let entry = AlarmEntry(id: entryID, backupMinutes: 30)
        let pending = BackupStopAnalytics.pendingEvent(
            role: .backup(entryID: entryID),
            entry: entry,
            snoozesBefore: nil,
            hour: 6,
            timestamp: now
        )
        #expect(pending?.intProperties?["minutes"] == 30)
        #expect(pending?.intProperties?["snoozes_before"] == nil)
        #expect(pending?.postHogProperties["snoozes_before"] == nil)
    }
}
