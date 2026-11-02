import Foundation
import StoreKit
import os

/// 広告判定に必要なシステム情報を集めて `AdPolicy` に渡す（#111）。
/// - originalAppVersion: StoreKit 2 の AppTransaction（取得失敗は nil → 出さない）
/// - region: Storefront の国 → 端末の地域 → limitedOnly
@Observable
@MainActor
final class AdEligibilityService {
    static let shared = AdEligibilityService()

    private let logger = Logger(subsystem: "com.tkysdev.customsoundalarm", category: "Ads")

    private(set) var originalAppVersion: String?
    private(set) var region: AdRegion = .limitedOnly
    private(set) var isLoaded = false

    @ObservationIgnored
    private var loadTask: Task<Void, Never>?

    private init() {}

    /// AppTransaction / Storefront を一度だけ読む。
    func load() async {
        if isLoaded { return }
        if let loadTask {
            await loadTask.value
            return
        }

        let task = Task { @MainActor in
            var version: String?
            do {
                let result = try await AppTransaction.shared
                if case .verified(let transaction) = result {
                    version = transaction.originalAppVersion
                }
            } catch {
                self.logger.info("AppTransaction unavailable: \(error.localizedDescription, privacy: .public)")
            }

            let storefrontCountry = await Storefront.current?.countryCode
            let deviceRegion = Locale.current.region?.identifier

            self.originalAppVersion = version
            self.region = AdRegionLogic.region(
                storefrontCountryCode: storefrontCountry,
                deviceRegionCode: deviceRegion
            )
            self.isLoaded = true
        }

        loadTask = task
        await task.value
        loadTask = nil
    }

    /// 枠の表示可否を判定する（AdsConfig のスイッチは含まない）。
    func decision(for slot: AdSlotKind, now: Date = Date()) async -> AdDecision {
        await load()
        return AdPolicy(input: policyInput(now: now)).decision(for: slot)
    }

    /// スクリーンショット用の上書きを含む入力（DEBUGのみ）。
    private func policyInput(now: Date) -> AdPolicyInput {
#if DEBUG
        if AppGroup.isUITestForceAdsEligible {
            return AdPolicyInput(
                now: now,
                timeZone: .current,
                firstLaunchDate: now.addingTimeInterval(-30 * 24 * 60 * 60),
                originalAppVersion: String(AdsConfig.introductionBuild),
                introductionBuild: AdsConfig.introductionBuild,
                isPro: false,
                lastInterstitialShownAt: nil,
                region: .standard
            )
        }
#endif
        return AdPolicyInput(
            now: now,
            timeZone: .current,
            firstLaunchDate: AppGroup.firstLaunchDate,
            originalAppVersion: originalAppVersion,
            introductionBuild: AdsConfig.introductionBuild,
            isPro: Entitlements.shared.isPro,
            lastInterstitialShownAt: AppGroup.lastInterstitialShownAt,
            region: region
        )
    }
}

/// `ad_slot_eligible` / `ad_shown` / `ad_failed` の送信を一元化する（#111 / #147）。
@MainActor
enum AdReporting {
    static func report(slot: AdSlotKind, decision: AdDecision) {
        AnalyticsService.shared.capture(.adSlotEligible(
            slot: slot,
            allowed: decision.allowed,
            reason: decision.reason,
            region: decision.region
        ))
    }

    static func reportShown(slot: AdSlotKind) {
        AnalyticsService.shared.capture(.adShown(slot: slot))
    }

    static func reportFailed(slot: AdSlotKind, error: Error) {
        AnalyticsService.shared.capture(.adFailed(
            slot: slot,
            code: AdFailureCode.from(error).rawValue
        ))
    }
}
