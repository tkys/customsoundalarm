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
            customSoundCount: 2,
            playlistCount: 0,
            hasShown: false
        ) == .secondImport)
        #expect(PlaylistUnlockLogic.trigger(
            hasPending: false,
            customSoundCount: 2,
            playlistCount: 0,
            hasShown: false
        ) == .existingUser)
    }

    @Test
    func existingUserTriggerDoesNotDoubleWithSecondImportAfterShown() {
        #expect(PlaylistUnlockLogic.trigger(
            hasPending: false,
            customSoundCount: 2,
            playlistCount: 0,
            hasShown: true
        ) == nil)
        #expect(PlaylistUnlockLogic.trigger(
            hasPending: true,
            customSoundCount: 2,
            playlistCount: 0,
            hasShown: true
        ) == nil)
    }

    @Test
    func existingUserTriggerIsSkippedWhenConditionsAreNotMet() {
        #expect(PlaylistUnlockLogic.trigger(
            hasPending: false,
            customSoundCount: 1,
            playlistCount: 0,
            hasShown: false
        ) == nil)
        #expect(PlaylistUnlockLogic.trigger(
            hasPending: false,
            customSoundCount: 2,
            playlistCount: 1,
            hasShown: false
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
