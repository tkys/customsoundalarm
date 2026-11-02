import Foundation

/// 広告 SDK に渡すプライバシー設定（#147）。
///
/// EEA・英国・スイス（`AdRegion.limitedOnly`）では同意画面を出さず、
/// Google の Limited ads（LTD）だけを有効にする。それ以外の地域でも
/// パーソナライズ広告は無効にする（ATT を要求しない方針のため）。
struct AdSDKPrivacy: Equatable, Sendable {
    /// 判定に使った地域
    let region: AdRegion
    /// Limited ads を有効にするか（`gad_has_consent_for_cookies = 0`）
    let limitedAds: Bool
    /// 同意画面（UMP）を出すか。このアプリでは常に false。
    let presentsConsentForm: Bool
    /// パーソナライズ広告を無効にするか。このアプリでは常に true。
    let personalizationDisabled: Bool

    /// 地域から設定を決める純ロジック。
    static func resolve(region: AdRegion) -> AdSDKPrivacy {
        AdSDKPrivacy(
            region: region,
            limitedAds: region == .limitedOnly,
            presentsConsentForm: false,
            personalizationDisabled: true
        )
    }
}

/// `AdSDKPrivacy` を実際の SDK / UserDefaults に反映する。
enum AdSDKPrivacyApplier {
    /// Google Mobile Ads SDK が Limited ads を有効にするためのキー。
    /// https://developers.google.com/admob/ios/global-settings
    static let limitedAdsConsentKey = "gad_has_consent_for_cookies"

    /// SDK の初期化前に呼ぶこと。
    ///
    /// - Limited ads 地域: `0` を書き、パーソナライズを無効にする。
    /// - それ以外: 過去に書いた値を消し、パーソナライズを無効にする。
    static func apply(_ privacy: AdSDKPrivacy, defaults: UserDefaults = .standard) {
        if privacy.limitedAds {
            defaults.set(0, forKey: limitedAdsConsentKey)
        } else {
            defaults.removeObject(forKey: limitedAdsConsentKey)
        }
    }
}
