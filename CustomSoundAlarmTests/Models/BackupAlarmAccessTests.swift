import Testing
import Foundation
@testable import CustomSoundAlarm

struct BackupAlarmAccessTests {

    @Test
    func earlyAccess_isAvailableForEveryone() {
        #expect(BackupAlarmAccess.isAvailable(
            isPro: false, earlyAccessGranted: false, isEarlyAccessPeriod: true
        ))
        #expect(BackupAlarmAccess.isAvailable(
            isPro: true, earlyAccessGranted: false, isEarlyAccessPeriod: true
        ))
    }

    @Test
    func afterLaunch_proCanUse() {
        #expect(BackupAlarmAccess.isAvailable(
            isPro: true, earlyAccessGranted: false, isEarlyAccessPeriod: false
        ))
    }

    @Test
    func afterLaunch_earlyAccessGrantCanUse() {
        #expect(BackupAlarmAccess.isAvailable(
            isPro: false, earlyAccessGranted: true, isEarlyAccessPeriod: false
        ))
    }

    @Test
    func afterLaunch_nonProWithoutGrantCannotUse() {
        #expect(!BackupAlarmAccess.isAvailable(
            isPro: false, earlyAccessGranted: false, isEarlyAccessPeriod: false
        ))
    }

    @Test
    func grant_onlyWhenEnabledDuringEarlyAccess() {
        #expect(BackupAlarmAccess.shouldGrantEarlyAccess(isEnabled: true, isEarlyAccessPeriod: true))
        #expect(!BackupAlarmAccess.shouldGrantEarlyAccess(isEnabled: false, isEarlyAccessPeriod: true))
        #expect(!BackupAlarmAccess.shouldGrantEarlyAccess(isEnabled: true, isEarlyAccessPeriod: false))
    }

    @Test
    func appGroupGrantFlag_roundTrip() {
        let original = AppGroup.backupEarlyAccessGranted
        defer { AppGroup.backupEarlyAccessGranted = original }

        AppGroup.backupEarlyAccessGranted = true
        #expect(AppGroup.backupEarlyAccessGranted)
        AppGroup.backupEarlyAccessGranted = false
        #expect(!AppGroup.backupEarlyAccessGranted)
    }
}
