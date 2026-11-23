import SwiftUI

/// バナー広告の置き場所（#111）。
/// このIssueでは SDK を入れないため、`AdsConfig.isEnabled == false` の間は
/// 高さ0・何も描画しない。判定と計測だけは行う。
struct AdSlot: View {
    let slot: AdSlotKind
    /// 試聴中など、その画面で出したくない状態のとき true（#266）。
    var isSuppressed = false

    @State private var service = AdEligibilityService.shared
    @State private var allowed = false

    var body: some View {
        Group {
            if !isSuppressed,
               AdSlotLayout.shouldRender(isEnabled: AdsConfig.isEnabled, allowed: allowed) {
                // 1.9.0 で Google Mobile Ads のバナーに差し替える
                Color.clear
                    .frame(height: AdSlotLayout.height(isEnabled: true))
                    .accessibilityHidden(true)
            }
        }
        .frame(height: isSuppressed ? 0 : AdSlotLayout.height(isEnabled: AdsConfig.isEnabled))
        .accessibilityIdentifier("adSlot.\(slot.rawValue)")
        .task {
            guard !isSuppressed else { return }
            let decision = await service.decision(for: slot)
            allowed = decision.allowed
            AdReporting.report(slot: slot, decision: decision)
        }
    }
}
