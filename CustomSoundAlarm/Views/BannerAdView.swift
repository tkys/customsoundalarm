import GoogleMobileAds
import SwiftUI
import UIKit

/// 適応型バナー（Google Mobile Ads）の SwiftUI ラッパー（#147）。
///
/// `largeAnchoredAdaptiveBanner(width:)` で幅に合わせた高さを要求し、
/// 読み込みに成功したら実際の高さを、失敗したら 0 をコールバックする。
struct BannerAdView: UIViewRepresentable {
    let adUnitID: String
    let width: CGFloat
    let onAdLoaded: (CGFloat) -> Void
    let onImpression: () -> Void
    let onFailure: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onAdLoaded: onAdLoaded,
            onImpression: onImpression,
            onFailure: onFailure
        )
    }

    func makeUIView(context: Context) -> BannerView {
        // 幅が決まる前（0）にリクエストしない。幅が決まったら updateUIView で読み込む。
        let adSize = width > 0 ? largeAnchoredAdaptiveBanner(width: width) : AdSizeBanner
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = adUnitID
        banner.delegate = context.coordinator
        banner.rootViewController = AdPresentationContext.topViewController()
        context.coordinator.loadedWidth = width
        if width > 0 {
            banner.load(Request())
        }
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {
        guard width > 0 else { return }
        guard abs(width - context.coordinator.loadedWidth) > 1 else { return }

        context.coordinator.loadedWidth = width
        banner.adUnitID = adUnitID
        banner.rootViewController = AdPresentationContext.topViewController()
        banner.adSize = largeAnchoredAdaptiveBanner(width: width)
        banner.load(Request())
    }

    @MainActor
    final class Coordinator: NSObject, BannerViewDelegate {
        private let onAdLoaded: (CGFloat) -> Void
        private let onImpression: () -> Void
        private let onFailure: (Error) -> Void
        var loadedWidth: CGFloat = 0

        init(
            onAdLoaded: @escaping (CGFloat) -> Void,
            onImpression: @escaping () -> Void,
            onFailure: @escaping (Error) -> Void
        ) {
            self.onAdLoaded = onAdLoaded
            self.onImpression = onImpression
            self.onFailure = onFailure
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            onAdLoaded(bannerView.adSize.size.height)
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            onFailure(error)
        }

        func bannerViewDidRecordImpression(_ bannerView: BannerView) {
            onImpression()
        }
    }
}
