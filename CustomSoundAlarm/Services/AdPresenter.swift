import Foundation

/// 全画面広告を出すタイミング（#111）。
enum AdPresentTrigger: Sendable {
    case importSaved
}

/// 全画面広告の呼び出し口。
/// このIssueでは SDK を入れないため、`AdsConfig.isEnabled == false` の間は
/// 判定と計測だけを行い、何も表示しない。
@MainActor
enum AdPresenter {
    static func presentInterstitialIfAllowed(after trigger: AdPresentTrigger) async {
        let slot: AdSlotKind
        switch trigger {
        case .importSaved:
            slot = .interstitialImportSaved
        }

        let decision = await AdEligibilityService.shared.decision(for: slot)
        AdReporting.report(slot: slot, decision: decision)

        guard AdsConfig.isEnabled, decision.allowed else { return }

        // 1.9.0: ここで Google Mobile Ads の全画面を表示する。
        // 表示した時点で週1回の起点を更新する（今は到達しない）。
        AppGroup.lastInterstitialShownAt = Date()
    }
}
