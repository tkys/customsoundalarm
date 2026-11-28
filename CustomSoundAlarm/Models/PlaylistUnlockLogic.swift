import Foundation

/// プレイリストの解放を出す理由（#216 / #280）。
enum PlaylistUnlockTrigger: String, Equatable, Sendable, CaseIterable {
    /// 2つ目の音を取り込んだ（#216）
    case secondImport = "second_import"
    /// 1.8.5 より前から2つ以上取り込んでいた（#280）
    case existingUser = "existing_user"
}

/// プレイリストの「解放」を出す条件（#216 / #280）。
enum PlaylistUnlockLogic {
    /// 解放を出す取り込み音の数。
    static let requiredCustomSoundCount = 2

    /// 既存の人にも出すか（#280）。1.8.5 では止める（#322）。
    /// 作った後に「使うアラームを選ぶ」流れが無いまま出すと、
    /// 一度きりの表示が行き止まりで終わるため。選ぶ流れと一緒に戻す。
    static let offersToExistingUsers = false

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

    /// 既存の人（1.8.5 より前から2つ以上取り込んでいた人）に出すか（#280）。
    static func shouldOfferToExistingUser(
        customSoundCount: Int,
        playlistCount: Int,
        hasShown: Bool
    ) -> Bool {
        !hasShown
            && playlistCount == 0
            && customSoundCount >= requiredCustomSoundCount
    }

    /// いま出す理由。2つ目の取り込みが待っているならそれを優先する（#280）。
    /// 表示済みなら nil。
    static func trigger(
        hasPending: Bool,
        customSoundCount: Int,
        playlistCount: Int,
        hasShown: Bool,
        offersToExistingUsers: Bool = PlaylistUnlockLogic.offersToExistingUsers
    ) -> PlaylistUnlockTrigger? {
        guard !hasShown else { return nil }
        if hasPending { return .secondImport }
        guard offersToExistingUsers, shouldOfferToExistingUser(
            customSoundCount: customSoundCount,
            playlistCount: playlistCount,
            hasShown: hasShown
        ) else { return nil }
        return .existingUser
    }

    /// いまシートを出してよいか。
    /// 鳴動中・ナイトモード中・別のシート表示中は出さない。
    static func canPresent(
        trigger: PlaylistUnlockTrigger?,
        isRinging: Bool,
        isNightMode: Bool,
        hasAnotherSheet: Bool = false
    ) -> Bool {
        trigger != nil && !isRinging && !isNightMode && !hasAnotherSheet
    }
}
