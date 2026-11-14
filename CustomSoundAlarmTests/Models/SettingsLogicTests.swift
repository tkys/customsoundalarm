import Testing
import Foundation
@testable import CustomSoundAlarm

/// 設定画面の純ロジック（#204）。
struct SettingsLogicTests {

    @Test
    func versionString_showsShortVersionAndBuild() {
        #expect(SettingsLogic.versionString(shortVersion: "1.8.2", build: "14") == "1.8.2 (14)")
    }

    @Test
    func versionString_handlesMissingValues() {
        #expect(SettingsLogic.versionString(shortVersion: nil, build: nil) == "— (—)")
        #expect(SettingsLogic.versionString(shortVersion: "", build: "14") == "— (14)")
        #expect(SettingsLogic.versionString(shortVersion: "1.8.2", build: "") == "1.8.2 (—)")
    }

    @Test
    func howToURL_usesTheDeviceLanguage() {
        let cases: [(String, String)] = [
            ("ja_JP", "ja/"),
            ("fr_FR", "fr/"),
            ("de_DE", "de/"),
            ("es_ES", "es/"),
            ("it_IT", "it/"),
            ("nl_NL", "nl/"),
            ("ko_KR", "ko/"),
            ("pl_PL", "pl/"),
            ("cs_CZ", "cs/"),
            ("ar_SA", "ar/"),
            ("pt_BR", "pt-br/"),
            ("zh_Hans_CN", "zh-hans/"),
        ]
        for (identifier, path) in cases {
            let url = SettingsLogic.howToURL(locale: Locale(identifier: identifier))
            #expect(
                url.absoluteString == "https://mysoundalarm.com/\(path)howto.html",
                "\(identifier): \(url)"
            )
        }
    }

    @Test
    func howToURL_fallsBackToEnglish() {
        for identifier in ["en_US", "ru_RU", "zh_Hant_TW", "th_TH"] {
            let url = SettingsLogic.howToURL(locale: Locale(identifier: identifier))
            #expect(
                url.absoluteString == "https://mysoundalarm.com/howto.html",
                "\(identifier): \(url)"
            )
        }
    }

    @Test
    func mailBody_containsDeviceInfoAndNoAlarmOrSoundData() {
        let body = SettingsLogic.mailBody(
            appVersion: "1.8.2 (14)",
            osVersion: "26.5",
            deviceModel: "iPhone (iPhone18,1)"
        )
        // お礼の定型文は入れず、空行2つのあとに区切りと端末情報だけ
        #expect(body.hasPrefix("\n\n---\n"))
        #expect(!body.contains("Thanks"))
        #expect(!body.lowercased().contains("please write"))
        #expect(body.contains("1.8.2 (14)"))
        #expect(body.contains("26.5"))
        #expect(body.contains("iPhone (iPhone18,1)"))
        // アラームの時刻・ラベル・音の名前は入れない
        #expect(!body.contains("07:00"))
        #expect(!body.contains("PresetMarimba.caf"))
        #expect(!body.contains("朝"))
    }

    @Test
    func links_pointToThePublishedPages() {
        #expect(SettingsLogic.supportURL.absoluteString == "https://mysoundalarm.com/support.html")
        #expect(SettingsLogic.privacyURL.absoluteString == "https://mysoundalarm.com/privacy.html")
        #expect(SettingsLogic.reviewURL.absoluteString == "https://apps.apple.com/app/id6760616800?action=write-review")
    }

    /// 旧 URL（tkys.github.io）は http:// への転送を返し、iOS の ATS で読めないため新ドメインを直接指す。
    @Test
    func appUsesTheNewDomainDirectly() {
        #expect(SettingsLogic.supportEmail == "support@mysoundalarm.com")
        #expect(URLSessionAppConfigFetcher.defaultURL.absoluteString == "https://mysoundalarm.com/app-config.json")
    }
}
