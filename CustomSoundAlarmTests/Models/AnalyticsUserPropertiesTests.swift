import Testing
import Foundation
@testable import CustomSoundAlarm

struct AnalyticsUserPropertiesTests {

    @Test
    func backupAlarmCount_countsEntriesWithBackupOn() {
        let alarms = [
            AlarmEntry(backupMinutes: 15),
            AlarmEntry(backupMinutes: 30),
            AlarmEntry(backupMinutes: nil)
        ]
        #expect(AnalyticsUserProperties.backupAlarmCount(alarms: alarms) == 2)
        #expect(AnalyticsUserProperties.backupAlarmCount(alarms: []) == 0)
    }

    @Test
    func firstInstallBuild_parsesBuildNumber() {
        #expect(AnalyticsUserProperties.firstInstallBuild(fromOriginalAppVersion: "6") == 6)
        #expect(AnalyticsUserProperties.firstInstallBuild(fromOriginalAppVersion: " 12 ") == 12)
    }

    @Test
    func firstInstallBuild_nilForUnavailableOrInvalid() {
        #expect(AnalyticsUserProperties.firstInstallBuild(fromOriginalAppVersion: nil) == nil)
        #expect(AnalyticsUserProperties.firstInstallBuild(fromOriginalAppVersion: "") == nil)
        #expect(AnalyticsUserProperties.firstInstallBuild(fromOriginalAppVersion: "1.0") == nil)
        #expect(AnalyticsUserProperties.firstInstallBuild(fromOriginalAppVersion: "abc") == nil)
        #expect(AnalyticsUserProperties.firstInstallBuild(fromOriginalAppVersion: "-1") == nil)
    }
}
