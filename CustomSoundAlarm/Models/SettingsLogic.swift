import Foundation
import UIKit

/// 設定画面の純ロジック（#204）。
enum SettingsLogic {
    static let supportEmail = "tkysyskw.dev@gmail.com"
    static let siteBase = "https://tkys.github.io/customsoundalarm/"

    static let supportURL = URL(string: siteBase + "support.html")!
    static let privacyURL = URL(string: siteBase + "privacy.html")!
    static let reviewURL = URL(string: "https://apps.apple.com/app/id6760616800?action=write-review")!

    /// 「1.8.2 (14)」の形。
    static func versionString(shortVersion: String?, build: String?) -> String {
        let version = shortVersion.flatMap { $0.isEmpty ? nil : $0 } ?? "—"
        let buildNumber = build.flatMap { $0.isEmpty ? nil : $0 } ?? "—"
        return "\(version) (\(buildNumber))"
    }

    static func appVersionString(bundle: Bundle = .main) -> String {
        versionString(
            shortVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }

    /// 端末の言語に合う使い方ページ。対応するページが無ければ英語。
    static func howToURL(locale: Locale) -> URL {
        let language = locale.language.languageCode?.identifier.lowercased() ?? "en"
        let script = locale.language.script?.identifier.lowercased()

        let path: String
        switch language {
        case "ja": path = "ja/"
        case "fr": path = "fr/"
        case "de": path = "de/"
        case "es": path = "es/"
        case "it": path = "it/"
        case "nl": path = "nl/"
        case "ko": path = "ko/"
        case "pl": path = "pl/"
        case "cs": path = "cs/"
        case "ar": path = "ar/"
        case "pt": path = "pt-br/"
        case "zh":
            // サイトにあるのは簡体字のページだけ。繁体字は英語に回す。
            path = script == "hans" ? "zh-hans/" : ""
        default:
            path = ""
        }
        return URL(string: siteBase + path + "howto.html")!
    }

    /// メール本文。端末情報を末尾に足し、アラームや音の情報は入れない。
    static func mailBody(
        appVersion: String,
        osVersion: String,
        deviceModel: String
    ) -> String {
        String(
            format: String(localized: "settings_mail_body"),
            appVersion,
            osVersion,
            deviceModel
        )
    }

    /// 「iPhone (iPhone18,1)」の形。機種名とハードウェア識別子だけ。
    @MainActor
    static func deviceModelName(
        model: String = UIDevice.current.model,
        machine: String = hardwareMachine()
    ) -> String {
        "\(model) (\(machine))"
    }

    private static func hardwareMachine() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
    }
}
