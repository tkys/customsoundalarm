import Foundation
import os

/// App Store レビュー依頼の出し分けを管理する。
///
/// 方針（「発火実績ベース」）:
/// - アラームが実際に発火した「日数」が閾値に達した定着ユーザーにのみ依頼する
///   （繰り返しアラームで水増しされないよう、同一日は 1 回しか数えない）。
/// - 同一アプリバージョンで一度依頼したら、そのバージョンでは再依頼しない
///   （OS 側の「年3回まで」制限に加えた自前ガード）。
/// - **最後のアラーム発火から 4 時間以内は依頼しない**（鳴動直後の眠い瞬間を避け、
///   ユーザーが自ら落ち着いて開いたときに出す・#84）。
///   かつては「発火があった起動セッションでは出さない」（プロセス内フラグ）だったが、
///   iOS はサスペンドしてプロセスが数日生き続けるため一度立てると永久にブロックされ、
///   依頼が一事実上出ない状態になっていた。**プロセス寿命に依存する状態は持たないこと**。
///
/// StoreKit への依存は持たない。実際の OS へのレビュー要求は呼び出し側から
/// クロージャで注入する（テスト容易性と関心の分離のため）。
@MainActor
final class ReviewRequestManager {
    static let shared = ReviewRequestManager()

    /// 発火した「日数」がこの値に達したら定着ユーザーとみなす。
    static let firedDayThreshold = 3

    /// 最後のアラーム発火からこの時間（秒）以内は依頼しない（#84）
    static let postFireSuppressInterval: TimeInterval = 4 * 60 * 60

    private enum Key {
        static let firedDayCount = "review.firedDayCount"
        static let lastFiredDay = "review.lastFiredDay"
        static let lastRequestedVersion = "review.lastRequestedVersion"
        /// 最後のアラーム発火時刻（#84: 発火からの経過時間判定に使う）
        static let lastFiredAt = "review.lastFiredAt"
    }

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.tkysdev.customsoundalarm", category: "ReviewRequest")

    init(defaults: UserDefaults = AppGroup.userDefaults) {
        self.defaults = defaults
    }

    // MARK: - 記録

    /// アラーム発火を記録する。
    /// 1 日に何度呼ばれても、その日を初めて記録するときだけ日数を加算する。
    /// 最終発火時刻は呼び出しのたびに更新する（同日の再発火＝スヌーズでも
    /// 抑制期間が延長されるようにするため・#84）。
    func recordAlarmFired(now: Date = Date(), calendar: Calendar = .current) {
        defaults.set(now, forKey: Key.lastFiredAt)

        if let last = defaults.object(forKey: Key.lastFiredDay) as? Date,
           calendar.isDate(last, inSameDayAs: now) {
            return // 同じ日は加算しない
        }

        let newCount = firedDayCount + 1
        defaults.set(newCount, forKey: Key.firedDayCount)
        defaults.set(now, forKey: Key.lastFiredDay)
        logger.info("Alarm fired recorded — firedDayCount=\(newCount)")
    }

    // MARK: - 判定

    /// アラームが発火した日数（永続値）。
    var firedDayCount: Int { defaults.integer(forKey: Key.firedDayCount) }

    /// 最後のアラーム発火から抑制期間（4時間）が過ぎているか（#84・純粋関数）。
    ///
    /// - Parameters:
    ///   - lastFiredAt: 最後のアラーム発火時刻（nil = 一度も発火記録がない）
    ///   - now: 判定基準時刻
    /// - Returns: 依頼を出してよい（抑制期間経過済み、または発火記録なし）
    static func isPastPostFireInterval(lastFiredAt: Date?, now: Date) -> Bool {
        guard let lastFiredAt else { return true }
        return now.timeIntervalSince(lastFiredAt) >= postFireSuppressInterval
    }

    /// 永続状態のみに基づく依頼可否（発火からの経過時間も含む）。テスト対象の純粋判定。
    func shouldRequestReview(appVersion: String, now: Date = Date()) -> Bool {
        guard firedDayCount >= Self.firedDayThreshold else { return false }
        let lastVersion = defaults.string(forKey: Key.lastRequestedVersion)
        guard lastVersion != appVersion else { return false }
        let lastFiredAt = defaults.object(forKey: Key.lastFiredAt) as? Date
        return Self.isPastPostFireInterval(lastFiredAt: lastFiredAt, now: now)
    }

    /// このバージョンで依頼済みとして記録する。
    func markRequested(appVersion: String) {
        defaults.set(appVersion, forKey: Key.lastRequestedVersion)
    }

    /// 条件を満たすときだけ `perform` を呼び、依頼済みとして記録する。
    /// ブロックした理由と実行の両方を計測する（#84・OS がダイアログを表示したかは分からない）。
    /// - Parameters:
    ///   - appVersion: 現在のアプリバージョン（既定は Info.plist から）。
    ///   - now: 判定基準時刻（テスト用に注入可能）。
    ///   - perform: 実際に OS のレビュー要求を出すクロージャ（StoreKit の requestReview 等）。
    /// - Returns: 実際に依頼を出したか。
    @discardableResult
    func requestReviewIfAppropriate(
        appVersion: String = ReviewRequestManager.currentAppVersion,
        now: Date = Date(),
        perform: () -> Void
    ) -> Bool {
        // 発火直後の抑制は「最終発火からの経過時間」で判定する（プロセス寿命非依存・#84）
        let lastFiredAt = defaults.object(forKey: Key.lastFiredAt) as? Date
        guard Self.isPastPostFireInterval(lastFiredAt: lastFiredAt, now: now) else {
            AnalyticsService.shared.capture(.reviewRequestBlocked(reason: .postFire))
            return false
        }
        guard firedDayCount >= Self.firedDayThreshold else {
            AnalyticsService.shared.capture(.reviewRequestBlocked(reason: .belowThreshold))
            return false
        }
        guard defaults.string(forKey: Key.lastRequestedVersion) != appVersion else {
            AnalyticsService.shared.capture(.reviewRequestBlocked(reason: .alreadyRequestedVersion))
            return false
        }

        perform()
        markRequested(appVersion: appVersion)
        logger.info("Review requested (version=\(appVersion, privacy: .public))")
        AnalyticsService.shared.capture(.reviewRequested)
        return true
    }

    /// Info.plist の CFBundleShortVersionString。
    nonisolated static var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }
}
