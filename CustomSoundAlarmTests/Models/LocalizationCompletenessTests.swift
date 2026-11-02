import Testing
import Foundation
@testable import CustomSoundAlarm

/// 11 言語の追加（#149）で、キーの欠け・空文字・書式指定子の取り違え・
/// 「無料」等の断定表現が混ざらないようにする回帰テスト。
struct LocalizationCompletenessTests {

    private static let languages = [
        "en", "ja", "fr", "de", "es", "pt-BR", "it", "nl", "ko", "zh-Hans", "ar", "pl", "cs"
    ]

    private static let addedLanguages = [
        "fr", "de", "es", "pt-BR", "it", "nl", "ko", "zh-Hans", "ar", "pl", "cs"
    ]

    /// 音量ガイドの設定名は scripts/site/i18n_pages.py の用語集に合わせる。
    private static let volumeGuideTerms: [String: [String]] = [
        "fr": ["Réglages", "Sons et vibrations", "Sonnerie et alertes"],
        "de": ["Einstellungen", "Töne & Haptik", "Klingel- und Hinweistöne"],
        "es": ["Ajustes", "Sonidos y vibraciones", "Tonos y avisos"],
        "pt-BR": ["Ajustes", "Sons e Tátil", "Toques e Alertas"],
        "it": ["Impostazioni", "Suoni e feedback aptico", "Suoneria e avvisi"],
        "nl": ["Instellingen", "Geluiden en voelbare feedback", "Beltoon en meldingen"],
        "ko": ["설정", "사운드 및 햅틱", "벨소리 및 알림"],
        "zh-Hans": ["设置", "声音与触感", "铃声和提醒"],
        "ar": ["الإعدادات", "الأصوات والحس اللمسي", "النغمات والتنبيهات"],
        "pl": ["Ustawienia", "Dźwięki i haptyka", "Dzwonek i alerty"],
        "cs": ["Nastavení", "Zvuky a haptika", "Vyzvánění a upozornění"],
    ]

    private func strings(for language: String, resource: String = "Localizable") throws -> [String: String] {
        let path = try #require(
            Bundle.main.path(
                forResource: resource,
                ofType: "strings",
                inDirectory: nil,
                forLocalization: language
            ),
            "\(resource).strings for \(language)"
        )
        return try #require(NSDictionary(contentsOfFile: path) as? [String: String])
    }

    private func formatSpecifiers(in value: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"%(?:\d+\$)?(?:ld|d|@|%)"#)
        let range = NSRange(value.startIndex..., in: value)
        return regex.matches(in: value, range: range).compactMap {
            Range($0.range, in: value).map { String(value[$0]) }
        }
    }

    @Test
    func everyLanguageHasTheSameNonEmptyKeysAsEnglish() throws {
        let english = try strings(for: "en")
        #expect(english.count >= 170)

        for language in Self.languages {
            let localized = try strings(for: language)
            let missing = Set(english.keys).subtracting(localized.keys).sorted()
            let extra = Set(localized.keys).subtracting(english.keys).sorted()
            #expect(missing.isEmpty, "\(language) に足りないキー: \(missing)")
            #expect(extra.isEmpty, "\(language) に余分なキー: \(extra)")

            for (key, value) in localized {
                #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "\(language) \(key) が空")
            }
        }
    }

    @Test
    func formatSpecifiersMatchEnglish() throws {
        let english = try strings(for: "en")

        for language in Self.languages {
            let localized = try strings(for: language)
            for (key, englishValue) in english {
                guard let value = localized[key] else { continue }
                #expect(formatSpecifiers(in: value).sorted() == formatSpecifiers(in: englishValue).sorted(),
                        "\(language) \(key): 書式指定子が en と不一致（\(value)）")
            }
        }
    }

    @Test
    func addedLanguagesUseTheSiteGlossaryForTheVolumeGuide() throws {
        for language in Self.addedLanguages {
            let localized = try strings(for: language)
            let step = try #require(localized["volume_guide_step1"])
            for term in Self.volumeGuideTerms[language] ?? [] {
                #expect(step.contains(term), "\(language) volume_guide_step1 に「\(term)」がない: \(step)")
            }
        }
    }

    @Test
    func copyDoesNotClaimSomethingIsFreeOrAbsolute() throws {
        // 「無料」「絶対」等は審査・景表法の観点で避ける（#149）。
        let banned = [
            "free", "無料", "gratis", "gratuit", "kostenlos", "grátis", "gratuito",
            "免费", "免費", "무료", "مجان", "darmow", "zdarma",
            "絶対", "必ず", "perfect", "完璧"
        ]

        for language in Self.languages {
            let localized = try strings(for: language)
            for (key, value) in localized {
                let lowercased = value.lowercased()
                for word in banned {
                    #expect(!lowercased.contains(word.lowercased()),
                            "\(language) \(key) に断定・無料表現「\(word)」: \(value)")
                }
            }
        }
    }

    @Test
    func infoPlistStringsExistInEveryLanguage() throws {
        for language in Self.languages {
            let info = try strings(for: language, resource: "InfoPlist")
            for key in [
                "CFBundleDisplayName",
                "NSAlarmKitUsageDescription",
                "NSMicrophoneUsageDescription",
                "NSPhotoLibraryUsageDescription"
            ] {
                let value = try #require(info[key], "\(language) InfoPlist.strings に \(key) がない")
                #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            #expect(info["CFBundleDisplayName"] == "My Sound Alarm")
        }
    }
}
