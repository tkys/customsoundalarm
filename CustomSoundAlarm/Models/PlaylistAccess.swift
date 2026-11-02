import Foundation

/// プレイリスト／フェードの先行公開ルール（#151）。
/// 1.8.2 は先行公開中なので全員が使える。1.9.0 以降は PRO か権利保持者のみ。
enum PlaylistAccess {
    /// 1.8.2 は先行公開中
    static let isEarlyAccessPeriod: Bool = true

    static func canUse(
        isPro: Bool,
        earlyAccessGranted: Bool,
        isEarlyAccessPeriod: Bool = isEarlyAccessPeriod
    ) -> Bool {
        if isEarlyAccessPeriod { return true }
        return isPro || earlyAccessGranted
    }

    /// プレイリストかフェード設定を使った保存時に先行公開の権利を記録する
    static func shouldGrantEarlyAccess(
        usedPlaylistFeatures: Bool,
        isEarlyAccessPeriod: Bool = isEarlyAccessPeriod
    ) -> Bool {
        usedPlaylistFeatures && isEarlyAccessPeriod
    }
}
