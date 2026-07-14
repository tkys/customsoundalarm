import Foundation
import os

/// App Store レビュー依頼の出し分けを管理する。
///
/// 方針（「発火実績ベース」）:
/// - アラームが実際に発火した「日数」が閾値に達した定着ユーザーにのみ依頼する
///   （繰り返しアラームで水増しされないよう、同一日は 1 回しか数えない）。
/// - 同一アプリバージョンで一度依頼したら、そのバージョンでは再依頼しない
///   （OS 側の「年3回まで」制限に加えた自前ガード）。
/// - アラームが発火したその起動セッションでは依頼しない
///   （鳴動直後の眠い瞬間を避け、ユーザーが自ら落ち着いて開いた起動でのみ出す）。
///
/// StoreKit への依存は持たない。実際の OS へのレビュー要求は呼び出し側から
/// クロージャで注入する（テスト容易性と関心の分離のため）。
@MainActor
final class ReviewRequestManager {
    static let shared = ReviewRequestManager()

    /// 発火した「日数」がこの値に達したら定着ユーザーとみなす。
    static let firedDayThreshold = 3

    private enum Key {
        static let firedDayCount = "review.firedDayCount"
        static let lastFiredDay = "review.lastFiredDay"
        static let lastRequestedVersion = "review.lastRequestedVersion"
    }

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.tkysdev.customsoundalarm", category: "ReviewRequest")

    /// この起動セッション中にアラーム発火を記録したか（永続化しない）。
    private var didRecordFireThisSession = false

    init(defaults: UserDefaults = AppGroup.userDefaults) {
        self.defaults = defaults
    }

    // MARK: - 記録

    /// アラーム発火を記録する。
    /// 1 日に何度呼ばれても、その日を初めて記録するときだけ日数を加算する。
    func recordAlarmFired(now: Date = Date(), calendar: Calendar = .current) {
        didRecordFireThisSession = true

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

    /// 永続状態のみに基づく依頼可否（セッション状態は含まない）。テスト対象の純粋判定。
    func shouldRequestReview(appVersion: String) -> Bool {
        guard firedDayCount >= Self.firedDayThreshold else { return false }
        let lastVersion = defaults.string(forKey: Key.lastRequestedVersion)
        return lastVersion != appVersion
    }

    /// このバージョンで依頼済みとして記録する。
    func markRequested(appVersion: String) {
        defaults.set(appVersion, forKey: Key.lastRequestedVersion)
    }

    /// 条件を満たすときだけ `perform` を呼び、依頼済みとして記録する。
    /// - Parameters:
    ///   - appVersion: 現在のアプリバージョン（既定は Info.plist から）。
    ///   - perform: 実際に OS のレビュー要求を出すクロージャ（StoreKit の requestReview 等）。
    /// - Returns: 実際に依頼を出したか。
    @discardableResult
    func requestReviewIfAppropriate(
        appVersion: String = ReviewRequestManager.currentAppVersion,
        perform: () -> Void
    ) -> Bool {
        // 発火があった起動セッションでは出さない（眠い瞬間を避ける）。
        guard !didRecordFireThisSession else { return false }
        guard shouldRequestReview(appVersion: appVersion) else { return false }

        perform()
        markRequested(appVersion: appVersion)
        logger.info("Review requested (version=\(appVersion, privacy: .public))")
        return true
    }

    /// Info.plist の CFBundleShortVersionString。
    nonisolated static var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }
}
