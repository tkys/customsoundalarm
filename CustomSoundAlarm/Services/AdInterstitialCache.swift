import Foundation

/// 全画面広告のキャッシュ有効期限（#147）。
///
/// Google は読み込み後1時間で広告が失効すると案内している。
/// 余裕を見て55分を超えたら破棄し、表示前に読み込み直す。
enum AdInterstitialCache {
    /// キャッシュを新鮮とみなす最大経過時間（55分）
    static let maxAge: TimeInterval = 55 * 60

    /// 読み込み時刻から見て、まだ表示に使えるか。
    /// 端末時計が巻き戻った場合も安全側（破棄）に倒す。
    static func isFresh(loadedAt: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(loadedAt)
        return age >= 0 && age < maxAge
    }
}
