import Testing
import Foundation
@testable import CustomSoundAlarm

/// オンボーディングの表示判定（#98 Phase 1）を検証する。
struct OnboardingLogicTests {

    // MARK: - 表示判定（testShowsOnlyForFreshInstall）

    @Test
    func shouldShow_freshInstall_true() {
        // 未完了 × アラーム0件 × 取り込み音源0件 のときだけ表示
        #expect(OnboardingLogic.shouldShow(hasCompleted: false, alarmCount: 0, importedSoundCount: 0) == true)
    }

    @Test
    func shouldShow_completed_false() {
        #expect(OnboardingLogic.shouldShow(hasCompleted: true, alarmCount: 0, importedSoundCount: 0) == false)
    }

    @Test
    func shouldShow_hasAlarms_false() {
        #expect(OnboardingLogic.shouldShow(hasCompleted: false, alarmCount: 1, importedSoundCount: 0) == false)
        #expect(OnboardingLogic.shouldShow(hasCompleted: false, alarmCount: 5, importedSoundCount: 0) == false)
    }

    @Test
    func shouldShow_hasImportedSounds_false() {
        #expect(OnboardingLogic.shouldShow(hasCompleted: false, alarmCount: 0, importedSoundCount: 1) == false)
        #expect(OnboardingLogic.shouldShow(hasCompleted: false, alarmCount: 0, importedSoundCount: 3) == false)
    }

    // MARK: - 既存ユーザー（testExistingUserNeverSeesOnboarding）

    @Test
    func existingUser_isMarkedCompleted() {
        // アラームか取り込み音源が1件でもあれば表示せず、完了フラグが立つ
        let showsWithAlarm = OnboardingLogic.shouldShow(hasCompleted: false, alarmCount: 1, importedSoundCount: 0)
        #expect(showsWithAlarm == false)
        #expect(OnboardingLogic.shouldMarkCompleted(hasCompleted: false, shouldShowOnboarding: showsWithAlarm) == true)

        let showsWithSound = OnboardingLogic.shouldShow(hasCompleted: false, alarmCount: 0, importedSoundCount: 2)
        #expect(showsWithSound == false)
        #expect(OnboardingLogic.shouldMarkCompleted(hasCompleted: false, shouldShowOnboarding: showsWithSound) == true)
    }

    @Test
    func freshUser_isNotMarkedCompleted() {
        // 新規ユーザー（表示する）にはフラグを立てない → オンボ完了時に立てる
        let shows = OnboardingLogic.shouldShow(hasCompleted: false, alarmCount: 0, importedSoundCount: 0)
        #expect(shows == true)
        #expect(OnboardingLogic.shouldMarkCompleted(hasCompleted: false, shouldShowOnboarding: shows) == false)
    }

    @Test
    func completedUser_isNotMarkedAgain() {
        #expect(OnboardingLogic.shouldMarkCompleted(hasCompleted: true, shouldShowOnboarding: false) == false)
    }

    // MARK: - 許可要求の移動（testAuthorizationDeferredWhenOnboarding）

    @Test
    func authorization_deferredWhenOnboardingShows() {
        // オンボ表示時は起動時に許可要求しない（場面3で聞く）
        #expect(OnboardingLogic.shouldRequestAuthorizationAtLaunch(shouldShowOnboarding: true) == false)
    }

    @Test
    func authorization_requestedAtLaunchWithoutOnboarding() {
        // オンボを出さない人は従来どおり起動時に要求
        #expect(OnboardingLogic.shouldRequestAuthorizationAtLaunch(shouldShowOnboarding: false) == true)
    }

    // MARK: - OnboardingSource

    @Test
    func source_rawValues_matchAnalyticsIdentifiers() {
        #expect(OnboardingSource.video.rawValue == "video")
        #expect(OnboardingSource.audio.rawValue == "audio")
        #expect(OnboardingSource.preset.rawValue == "preset")
        #expect(OnboardingSource.later.rawValue == "later")
    }

    @Test
    func source_opensAddScreen_exceptLater() {
        #expect(OnboardingSource.video.opensAddScreen == true)
        #expect(OnboardingSource.audio.opensAddScreen == true)
        #expect(OnboardingSource.preset.opensAddScreen == true)
        // 「あとで」は一覧へ戻るだけ
        #expect(OnboardingSource.later.opensAddScreen == false)
    }
}
