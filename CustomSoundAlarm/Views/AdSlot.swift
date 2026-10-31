import SwiftUI

/// バナー広告の置き場所（#111）。
/// このIssueでは SDK を入れないため、`AdsConfig.isEnabled == false` の間は
/// 高さ0・何も描画しない。判定と計測だけは行う。
struct AdSlot: View {
    let slot: AdSlotKind

    @State private var service = AdEligibilityService.shared
    @State private var allowed = false

    var body: some View {
        Group {
            if AdSlotLayout.shouldRender(isEnabled: AdsConfig.isEnabled, allowed: allowed) {
                // 1.9.0 で Google Mobile Ads のバナーに差し替える
                Color.clear
                    .frame(height: AdSlotLayout.height(isEnabled: true))
                    .accessibilityHidden(true)
            }
        }
        .frame(height: AdSlotLayout.height(isEnabled: AdsConfig.isEnabled))
        .task {
            let decision = await service.decision(for: slot)
            allowed = decision.allowed
            AdReporting.report(slot: slot, decision: decision)
        }
    }
}
