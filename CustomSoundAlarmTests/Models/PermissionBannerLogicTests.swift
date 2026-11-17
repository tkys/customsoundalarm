import Testing
import Foundation
@testable import CustomSoundAlarm

/// 許可バナーの条件（#230）。
struct PermissionBannerLogicTests {

    @Test
    func showsWhenDeniedAndAnAlarmIsOn() {
        #expect(PermissionBannerLogic.shouldShow(status: .denied, enabledAlarmCount: 1))
        #expect(PermissionBannerLogic.action(for: .denied) == .openSettings)
    }

    @Test
    func doesNotShowWhenNoAlarmIsOn() {
        #expect(!PermissionBannerLogic.shouldShow(status: .denied, enabledAlarmCount: 0))
        #expect(!PermissionBannerLogic.shouldShow(status: .notDetermined, enabledAlarmCount: 0))
    }

    @Test
    func doesNotShowWhenAuthorized() {
        #expect(!PermissionBannerLogic.shouldShow(status: .authorized, enabledAlarmCount: 2))
        #expect(PermissionBannerLogic.action(for: .authorized) == nil)
    }

    @Test
    func notDeterminedAsksForPermission() {
        #expect(PermissionBannerLogic.shouldShow(status: .notDetermined, enabledAlarmCount: 1))
        #expect(PermissionBannerLogic.action(for: .notDetermined) == .requestAuthorization)
    }

    @Test
    func unknownAndFailedDoNotShow() {
        #expect(!PermissionBannerLogic.shouldShow(status: .unknown, enabledAlarmCount: 1))
        #expect(!PermissionBannerLogic.shouldShow(status: .requestFailed, enabledAlarmCount: 1))
    }
}
