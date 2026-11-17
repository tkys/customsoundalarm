import Foundation

/// プレイリストの「解放」を出す条件（#216）。
enum PlaylistUnlockLogic {
    /// 解放を出す取り込み音の数。
    static let requiredCustomSoundCount = 2

    /// 取り込んだ音が2つになった時点で、解放を待たせるか。
    /// プレイリストがある・すでに出した・2つ以外（3つ目以降）は出さない。
    static func shouldPend(
        previousCustomSoundCount: Int,
        newCustomSoundCount: Int,
        playlistCount: Int,
        hasShown: Bool
    ) -> Bool {
        guard !hasShown, playlistCount == 0 else { return false }
        return newCustomSoundCount == requiredCustomSoundCount
            && newCustomSoundCount > previousCustomSoundCount
    }

    /// いまシートを出してよいか。
    /// 鳴動中・ナイトモード中・別のシート表示中は出さない。
    static func canPresent(
        hasPending: Bool,
        hasShown: Bool,
        isRinging: Bool,
        isNightMode: Bool,
        hasAnotherSheet: Bool = false
    ) -> Bool {
        hasPending && !hasShown && !isRinging && !isNightMode && !hasAnotherSheet
    }
}
