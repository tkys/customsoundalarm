import Testing
import Foundation
@testable import CustomSoundAlarm

/// プレイリストの解放を出す条件（#216 / #280）。
struct PlaylistUnlockLogicTests {

    @Test
    func doesNotUnlockWhenNothingWasImportedBefore() {
        #expect(!PlaylistUnlockLogic.shouldPend(
            previousCustomSoundCount: 0,
            newCustomSoundCount: 1,
            playlistCount: 0,
            hasShown: false
        ))
    }

    @Test
    func unlocksWhenSecondSoundIsImported() {
        #expect(PlaylistUnlockLogic.shouldPend(
            previousCustomSoundCount: 1,
            newCustomSoundCount: 2,
            playlistCount: 0,
            hasShown: false
        ))
    }

    @Test
    func doesNotUnlockForThirdSound() {
        #expect(!PlaylistUnlockLogic.shouldPend(
            previousCustomSoundCount: 2,
            newCustomSoundCount: 3,
            playlistCount: 0,
            hasShown: false
        ))
    }

    @Test
    func doesNotUnlockWhenAPlaylistExists() {
        #expect(!PlaylistUnlockLogic.shouldPend(
            previousCustomSoundCount: 1,
            newCustomSoundCount: 2,
            playlistCount: 1,
            hasShown: false
        ))
    }

    @Test
    func doesNotUnlockWhenAlreadyShown() {
        #expect(!PlaylistUnlockLogic.shouldPend(
            previousCustomSoundCount: 1,
            newCustomSoundCount: 2,
            playlistCount: 0,
            hasShown: true
        ))
    }

    // MARK: - 既存の人への1回だけの提案（#280）

    @Test
    func existingUserWithTwoOrMoreSoundsAndNoPlaylistIsEligible() {
        #expect(PlaylistUnlockLogic.shouldOfferToExistingUser(
            customSoundCount: 2,
            playlistCount: 0,
            hasShown: false
        ))
        #expect(PlaylistUnlockLogic.shouldOfferToExistingUser(
            customSoundCount: 5,
            playlistCount: 0,
            hasShown: false
        ))
    }

    @Test
    func existingUserOfferIsSkippedWithOneSoundPlaylistOrAlreadyShown() {
        #expect(!PlaylistUnlockLogic.shouldOfferToExistingUser(
            customSoundCount: 1,
            playlistCount: 0,
            hasShown: false
        ))
        #expect(!PlaylistUnlockLogic.shouldOfferToExistingUser(
            customSoundCount: 2,
            playlistCount: 1,
            hasShown: false
        ))
        #expect(!PlaylistUnlockLogic.shouldOfferToExistingUser(
            customSoundCount: 2,
            playlistCount: 0,
            hasShown: true
        ))
    }

    @Test
    func secondImportTriggerWinsOverExistingUserTrigger() {
        #expect(PlaylistUnlockLogic.trigger(
            hasPending: true,
            hasFiredAlarm: true,
            customSoundCount: 2,
            playlistCount: 0,
            hasShown: false
        ) == .secondImport)
        #expect(PlaylistUnlockLogic.trigger(
            hasPending: false,
            hasFiredAlarm: false,
            customSoundCount: 2,
            playlistCount: 0,
            hasShown: false,
            offersToExistingUsers: true
        ) == .existingUser)
    }

    /// 新しく入れた人は、アラームが一度鳴るまで2つ目の取り込みのカードを待つ（#324）。
    @Test
    func secondImportWaitsUntilAnAlarmHasFired() {
        // 待ちあり × 鳴った記録なし → 出さない
        #expect(PlaylistUnlockLogic.trigger(
            hasPending: true,
            hasFiredAlarm: false,
            customSoundCount: 2,
            playlistCount: 0,
            hasShown: false
        ) == nil)
        // 待ちあり × 鳴った記録あり → 2つ目の取り込みとして出す
        #expect(PlaylistUnlockLogic.trigger(
            hasPending: true,
            hasFiredAlarm: true,
            customSoundCount: 2,
            playlistCount: 0,
            hasShown: false
        ) == .secondImport)
        // 待ちなし × 鳴った記録なし → 既存の人として出す
        #expect(PlaylistUnlockLogic.trigger(
            hasPending: false,
            hasFiredAlarm: false,
            customSoundCount: 2,
            playlistCount: 0,
            hasShown: false
        ) == .existingUser)
        // 待ちなし × 鳴った記録あり → 既存の人として出す
        #expect(PlaylistUnlockLogic.trigger(
            hasPending: false,
            hasFiredAlarm: true,
            customSoundCount: 2,
            playlistCount: 0,
            hasShown: false
        ) == .existingUser)
    }

    @Test
    func existingUserOfferIsOn() {
        #expect(PlaylistUnlockLogic.offersToExistingUsers)
        #expect(PlaylistUnlockLogic.trigger(
            hasPending: false,
            hasFiredAlarm: false,
            customSoundCount: 5,
            playlistCount: 0,
            hasShown: false
        ) == .existingUser)
    }

    @Test
    func existingUserTriggerDoesNotDoubleWithSecondImportAfterShown() {
        #expect(PlaylistUnlockLogic.trigger(
            hasPending: false,
            hasFiredAlarm: true,
            customSoundCount: 2,
            playlistCount: 0,
            hasShown: true
        ) == nil)
        #expect(PlaylistUnlockLogic.trigger(
            hasPending: true,
            hasFiredAlarm: true,
            customSoundCount: 2,
            playlistCount: 0,
            hasShown: true
        ) == nil)
    }

    @Test
    func existingUserTriggerIsSkippedWhenConditionsAreNotMet() {
        #expect(PlaylistUnlockLogic.trigger(
            hasPending: false,
            hasFiredAlarm: false,
            customSoundCount: 1,
            playlistCount: 0,
            hasShown: false,
            offersToExistingUsers: true
        ) == nil)
        #expect(PlaylistUnlockLogic.trigger(
            hasPending: false,
            hasFiredAlarm: false,
            customSoundCount: 2,
            playlistCount: 1,
            hasShown: false,
            offersToExistingUsers: true
        ) == nil)
    }

    @Test
    func presentOnlyWhenTriggeredAndCalm() {
        #expect(PlaylistUnlockLogic.canPresent(
            trigger: .secondImport,
            isRinging: false,
            isNightMode: false
        ))
        #expect(PlaylistUnlockLogic.canPresent(
            trigger: .existingUser,
            isRinging: false,
            isNightMode: false
        ))
        #expect(!PlaylistUnlockLogic.canPresent(
            trigger: nil,
            isRinging: false,
            isNightMode: false
        ))
        #expect(!PlaylistUnlockLogic.canPresent(
            trigger: .existingUser,
            isRinging: true,
            isNightMode: false
        ))
        #expect(!PlaylistUnlockLogic.canPresent(
            trigger: .existingUser,
            isRinging: false,
            isNightMode: true
        ))
        #expect(!PlaylistUnlockLogic.canPresent(
            trigger: .existingUser,
            isRinging: false,
            isNightMode: false,
            hasAnotherSheet: true
        ))
    }
}
