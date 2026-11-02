import SwiftUI

/// バナー広告の置き場所（#111 / #147）。
/// `AdsConfig.isEnabled == false` の間は高さ0・何も描画せず、判定と計測だけを行う。
/// 有効時は幅に合わせた適応型バナーを出し、読み込み失敗時は高さ0へ戻す。
struct AdSlot: View {
    let slot: AdSlotKind

    @State private var service = AdEligibilityService.shared
    @State private var decision: AdDecision?
    @State private var bannerHeight: CGFloat = 0

    var body: some View {
        Group {
            if AdsConfig.isEnabled, decision?.allowed == true, bannerHeight > 0 {
                GeometryReader { proxy in
                    BannerAdView(
                        adUnitID: AdsConfig.bannerUnitID,
                        width: proxy.size.width,
                        onAdLoaded: { height in
                            bannerHeight = height
                        },
                        onImpression: {
                            AdReporting.reportShown(slot: slot)
                        },
                        onFailure: { error in
                            bannerHeight = 0
                            AdReporting.reportFailed(slot: slot, error: error)
                        }
                    )
                    .frame(width: proxy.size.width, height: bannerHeight)
                }
                .frame(height: bannerHeight)
                // 暗い背景でも読みやすいよう、白いカードに載せる（広告側の配色に依存しない）
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .accessibilityIdentifier("adSlot.\(slot.rawValue)")
            }
        }
        .frame(height: renderedHeight)
        .task {
            let decision = await service.decision(for: slot)
            self.decision = decision
            AdReporting.report(slot: slot, decision: decision)

            guard AdsConfig.isEnabled, decision.allowed else { return }
            await AdSDKCoordinator.shared.prepare(decision: decision)
            bannerHeight = AdsConfig.bannerHeight
        }
    }

    private var renderedHeight: CGFloat {
        guard AdsConfig.isEnabled, decision?.allowed == true, bannerHeight > 0 else {
            return 0
        }
        return bannerHeight + 12
    }
}
