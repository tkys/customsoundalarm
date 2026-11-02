import Foundation
import GoogleMobileAds

/// 広告 SDK を初期化してよいかの純ロジック（#147）。
///
/// `AdPolicy` が許可していないユーザー（既存ユーザー・PRO・初回7日・夜間など）には
/// SDK を初期化しない。初期化しないことで広告リクエスト（通信）も発生させない。
enum AdSDKGate {
    static func mayInitialize(isEnabled: Bool, decision: AdDecision) -> Bool {
        isEnabled && decision.allowed
    }
}

/// SDK 初期化の抽象。テストで「呼ばれないこと」を検証するために注入する。
@MainActor
protocol AdSDKInitializing: AnyObject {
    func start(privacy: AdSDKPrivacy) async
}

/// 本番の Google Mobile Ads SDK 初期化。
@MainActor
final class GoogleMobileAdsInitializer: AdSDKInitializing {
    func start(privacy: AdSDKPrivacy) async {
        // Limited ads の UserDefaults は SDK 起動前に設定する必要がある。
        AdSDKPrivacyApplier.apply(privacy)
        MobileAds.shared.requestConfiguration.publisherPrivacyPersonalizationState = .disabled

        // 完了を待ってから広告を読み込む（最初のリクエストの遅延を減らす）。
        _ = await MobileAds.shared.start()
    }
}

/// SDK 初期化を一度だけ行うコーディネータ（#147）。
@MainActor
final class AdSDKCoordinator {
    static let shared = AdSDKCoordinator(initializer: GoogleMobileAdsInitializer())

    private let initializer: AdSDKInitializing
    private var initializationTask: Task<Void, Never>?
    private(set) var isInitialized = false

    init(initializer: AdSDKInitializing) {
        self.initializer = initializer
    }

    /// 判定が許可しているときだけ SDK を初期化する。
    /// 既に初期化済み・初期化中なら何もしない（通信も1回だけ）。
    func prepare(isEnabled: Bool = AdsConfig.isEnabled, decision: AdDecision) async {
        guard AdSDKGate.mayInitialize(isEnabled: isEnabled, decision: decision),
              !isInitialized else {
            return
        }

        if let initializationTask {
            await initializationTask.value
            return
        }

        let privacy = AdSDKPrivacy.resolve(region: decision.region)
        let initializer = self.initializer
        let task = Task { @MainActor in
            await initializer.start(privacy: privacy)
        }
        initializationTask = task
        await task.value
        isInitialized = true
        initializationTask = nil
    }
}
