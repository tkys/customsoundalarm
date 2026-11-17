import Testing
import Foundation
@testable import CustomSoundAlarm

/// プレイリストの解放を出す条件（#216）。
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

    @Test
    func presentOnlyWhenPendingAndCalm() {
        #expect(PlaylistUnlockLogic.canPresent(
            hasPending: true,
            hasShown: false,
            isRinging: false,
            isNightMode: false
        ))
        #expect(!PlaylistUnlockLogic.canPresent(
            hasPending: true,
            hasShown: false,
            isRinging: true,
            isNightMode: false
        ))
        #expect(!PlaylistUnlockLogic.canPresent(
            hasPending: true,
            hasShown: false,
            isRinging: false,
            isNightMode: true
        ))
        #expect(!PlaylistUnlockLogic.canPresent(
            hasPending: true,
            hasShown: false,
            isRinging: false,
            isNightMode: false,
            hasAnotherSheet: true
        ))
        #expect(!PlaylistUnlockLogic.canPresent(
            hasPending: false,
            hasShown: false,
            isRinging: false,
            isNightMode: false
        ))
        #expect(!PlaylistUnlockLogic.canPresent(
            hasPending: true,
            hasShown: true,
            isRinging: false,
            isNightMode: false
        ))
    }
}
