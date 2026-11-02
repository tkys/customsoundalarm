import GoogleMobileAds

/// 全画面広告を出すタイミング（#111 / #147）。
enum AdPresentTrigger: Sendable {
    case importSaved
}

/// 全画面広告の呼び出し口（#147）。
/// 判定と計測は常に行い、`AdsConfig.isEnabled` かつ `AdPolicy` が許可したときだけ
/// SDK を初期化して広告を読み込み・表示する。
@MainActor
enum AdPresenter {
    private static var interstitial: InterstitialAd?
    private static var interstitialLoadedAt: Date?
    private static var isLoadingInterstitial = false

    /// 取り込み画面を開いたときに事前読み込みする。
    /// 表示はしないので `ad_slot_eligible` は送らない（保存時に1回だけ送る）。
    static func preloadInterstitialIfAllowed() async {
        guard AdsConfig.isEnabled else { return }
        discardStaleInterstitialIfNeeded()
        guard interstitial == nil, !isLoadingInterstitial else { return }

        let slot = AdSlotKind.interstitialImportSaved
        let decision = await AdEligibilityService.shared.decision(for: slot)
        guard decision.allowed else { return }

        await AdSDKCoordinator.shared.prepare(decision: decision)
        guard interstitial == nil, !isLoadingInterstitial else { return }

        isLoadingInterstitial = true
        defer { isLoadingInterstitial = false }

        do {
            let ad = try await InterstitialAd.load(
                with: AdsConfig.interstitialUnitID,
                request: Request()
            )
            ad.fullScreenContentDelegate = InterstitialPresenterDelegate.shared
            interstitial = ad
            interstitialLoadedAt = Date()
        } catch {
            interstitial = nil
            interstitialLoadedAt = nil
            AdReporting.reportFailed(slot: slot, error: error)
        }
    }

    /// 取り込み保存後に全画面広告を出す。
    static func presentInterstitialIfAllowed(after trigger: AdPresentTrigger) async {
        let slot: AdSlotKind
        switch trigger {
        case .importSaved:
            slot = .interstitialImportSaved
        }

        let decision = await AdEligibilityService.shared.decision(for: slot)
        AdReporting.report(slot: slot, decision: decision)

        guard AdsConfig.isEnabled, decision.allowed else { return }
        await AdSDKCoordinator.shared.prepare(decision: decision)

        discardStaleInterstitialIfNeeded()
        if interstitial == nil {
            await preloadInterstitialIfAllowed()
        }
        guard let ad = interstitial, let presenter = await presentationController() else {
            return
        }

        do {
            try ad.canPresent(from: presenter)
        } catch {
            interstitial = nil
            interstitialLoadedAt = nil
            AdReporting.reportFailed(slot: slot, error: error)
            return
        }

        interstitial = nil
        interstitialLoadedAt = nil
        ad.fullScreenContentDelegate = InterstitialPresenterDelegate.shared
        ad.present(from: presenter)
    }

    /// 読み込み後55分を超えた広告は破棄する（Google は1時間で失効）。
    private static func discardStaleInterstitialIfNeeded(now: Date = Date()) {
        guard let loadedAt = interstitialLoadedAt else { return }
        guard !AdInterstitialCache.isFresh(loadedAt: loadedAt, now: now) else { return }
        interstitial = nil
        interstitialLoadedAt = nil
    }

    /// シートの閉じるアニメーション中は presentedViewController が残るため、
    /// 安定して広告を出せる VC が現れるまで待つ。
    private static func presentationController() async -> UIViewController? {
        for _ in 0..<20 {
            guard let root = AdPresentationContext.rootViewController() else { return nil }
            let presenter = root.presentedViewController ?? root
            if presenter.presentedViewController == nil {
                return presenter
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return AdPresentationContext.topViewController()
    }
}

/// 全画面広告の表示結果を計測する（#147）。
@MainActor
final class InterstitialPresenterDelegate: NSObject, FullScreenContentDelegate {
    static let shared = InterstitialPresenterDelegate()

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        // 実際に表示できた時点を週1回の起点にする。
        AppGroup.lastInterstitialShownAt = Date()
    }

    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        AdReporting.reportShown(slot: .interstitialImportSaved)
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        AdReporting.reportFailed(slot: .interstitialImportSaved, error: error)
    }
}
