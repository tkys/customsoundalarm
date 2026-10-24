import Foundation

/// 最終アラームの先行公開・権利判定（#110）。
///
/// このバージョンは先行公開中（`isEarlyAccessPeriod = true`）で、全員が使える。
/// 先行公開中にオンにした人は `AppGroup.backupEarlyAccessGranted` を記録し、
/// 正式に有料化した後も無料で使い続けられる。
enum BackupAlarmAccess {

    /// 先行公開期間か（このバージョンでは true 固定）
    static let isEarlyAccessPeriod: Bool = true

    /// 最終アラームを使えるか。
    static func isAvailable(
        isPro: Bool,
        earlyAccessGranted: Bool,
        isEarlyAccessPeriod: Bool = isEarlyAccessPeriod
    ) -> Bool {
        if isEarlyAccessPeriod { return true }
        return isPro || earlyAccessGranted
    }

    /// オンにしたときに先行公開の権利を記録すべきか。
    static func shouldGrantEarlyAccess(
        isEnabled: Bool,
        isEarlyAccessPeriod: Bool = isEarlyAccessPeriod
    ) -> Bool {
        isEnabled && isEarlyAccessPeriod
    }
}
