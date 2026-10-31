import Foundation

/// 広告の地域区分（#111 追記）。
/// EEA・英国・スイスは同意画面を出さず、制限付き広告のみを出す。
enum AdRegion: String, Codable, Sendable, Equatable {
    case standard
    case limitedOnly = "limited"
}

/// 国コードから広告地域を決める純ロジック。
enum AdRegionLogic {

    /// EEA（EU 27 + IS / LI / NO）＋ 英国 ＋ スイス
    static let limitedOnlyCountryCodes: Set<String> = [
        "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR",
        "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL",
        "PL", "PT", "RO", "SK", "SI", "ES", "SE",
        "IS", "LI", "NO",
        "GB", "CH"
    ]

    /// 国コードを地域に変換する。取得失敗（nil/空）は安全側の limitedOnly。
    static func region(forCountryCode code: String?) -> AdRegion {
        guard let code, !code.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .limitedOnly
        }
        let normalized = code.uppercased()
        return limitedOnlyCountryCodes.contains(normalized) ? .limitedOnly : .standard
    }

    /// ストアフロント国 → 端末の地域設定の順で解決する。
    /// どちらも取れない場合は limitedOnly。
    static func region(
        storefrontCountryCode: String?,
        deviceRegionCode: String?
    ) -> AdRegion {
        if let storefrontCountryCode,
           !storefrontCountryCode.trimmingCharacters(in: .whitespaces).isEmpty {
            return region(forCountryCode: storefrontCountryCode)
        }
        return region(forCountryCode: deviceRegionCode)
    }
}
