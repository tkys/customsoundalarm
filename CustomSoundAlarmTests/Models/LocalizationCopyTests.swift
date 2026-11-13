import Testing
import Foundation
@testable import CustomSoundAlarm

/// 画面に出る文言の回帰（#119）。
struct LocalizationCopyTests {

    @Test
    func noFinalAlarmCopyRemainsInLocalizableStrings() throws {
        for language in ["en", "ja"] {
            let path = try #require(
                Bundle.main.path(
                    forResource: "Localizable",
                    ofType: "strings",
                    inDirectory: nil,
                    forLocalization: language
                ),
                "Localizable.strings for \(language)"
            )
            let strings = try #require(
                NSDictionary(contentsOfFile: path) as? [String: String]
            )
            for (key, value) in strings {
                #expect(!value.contains("最終アラーム"), "\(language) \(key): \(value)")
                #expect(!value.lowercased().contains("final alarm"), "\(language) \(key): \(value)")
            }
        }
    }

    @Test
    func oversleepGuardCopyExists() throws {
        let path = try #require(
            Bundle.main.path(
                forResource: "Localizable",
                ofType: "strings",
                inDirectory: nil,
                forLocalization: "ja"
            )
        )
        let strings = try #require(NSDictionary(contentsOfFile: path) as? [String: String])
        #expect(strings["backup_alarm_toggle"] == "寝過ごし防止")
        #expect(strings["backup_alarm_row_badge"] == "寝過ごし防止あり")
        #expect(strings["backup_alarm_title_fmt"] == "寝過ごし防止：%@")
    }

    // MARK: - #197 休みの回数表記

    private static let languages = [
        "en", "ja", "fr", "de", "es", "pt-BR", "it", "nl", "ko", "zh-Hans", "ar", "pl", "cs"
    ]

    private func strings(for language: String) throws -> [String: String] {
        let path = try #require(
            Bundle.main.path(
                forResource: "Localizable",
                ofType: "strings",
                inDirectory: nil,
                forLocalization: language
            ),
            "Localizable.strings for \(language)"
        )
        return try #require(NSDictionary(contentsOfFile: path) as? [String: String])
    }

    @Test
    func skipOccurrenceCountsUseTimesInEveryLanguage() throws {
        let expected = [
            "en": "until %@ · %d times",
            "ja": "%@ まで・%d回",
            "fr": "jusqu’à %@ · %d fois",
            "de": "bis %@ · %d Mal",
            "es": "hasta el %@ · %d veces",
            "pt-BR": "até %@ · %d vezes",
            "it": "fino a %@ · %d volte",
            "nl": "tot %@ · %d keer",
            "ko": "%@ 까지 · %d회",
            "zh-Hans": "至 %@ · %d次",
            "ar": "حتى %@ · %d مرات",
            "pl": "do %@ · %d razy",
            "cs": "do %@ · %d krát",
        ]
        for language in Self.languages {
            let strings = try strings(for: language)
            #expect(
                strings["skip_all_row_fmt"] == expected[language],
                "\(language): \(strings["skip_all_row_fmt"] ?? "nil")"
            )
        }
    }

    @Test
    func restSheetKeepsAlarmCountInJapanese() throws {
        let strings = try strings(for: "ja")
        let row = try #require(strings["skip_all_row_fmt"])
        let top = try #require(strings["skip_all_active_fmt"])
        #expect(row.contains("回"))
        #expect(!row.contains("本"))
        #expect(top.contains("本"))
        #expect(!top.contains("回"))
    }

    @Test
    func globalSkipRowCopyExistsInEveryLanguage() throws {
        let expected = [
            "en": "Resting until %@",
            "ja": "%@ まで休み",
            "fr": "En pause jusqu’à %@",
            "de": "Pause bis %@",
            "es": "En pausa hasta el %@",
            "pt-BR": "Em pausa até %@",
            "it": "In pausa fino a %@",
            "nl": "Gepauzeerd tot %@",
            "ko": "%@ 까지 쉬기",
            "zh-Hans": "休息至 %@",
            "ar": "إيقاف مؤقت حتى %@",
            "pl": "Wstrzymane do %@",
            "cs": "Pozastaveno do %@",
        ]
        for language in Self.languages {
            let strings = try strings(for: language)
            #expect(
                strings["skip_row_global_fmt"] == expected[language],
                "\(language): \(strings["skip_row_global_fmt"] ?? "nil")"
            )
        }
    }
}
