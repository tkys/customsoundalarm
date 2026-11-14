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
            "ja": "%@ まで鳴らさない",
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

    @Test
    func repeatSummarySkipsUseEveryLanguage() throws {
        let holiday = [
            "en": "holidays excluded",
            "ja": "祝日を除く",
            "fr": "jours fériés exclus",
            "de": "Feiertage ausgenommen",
            "es": "festivos excluidos",
            "pt-BR": "feriados excluídos",
            "it": "festività escluse",
            "nl": "feestdagen uitgesloten",
            "ko": "공휴일 제외",
            "zh-Hans": "不含节假日",
            "ar": "بدون العطلات",
            "pl": "bez świąt",
            "cs": "bez svátků",
        ]
        let skipDays = [
            "en": "%d days off",
            "ja": "%d日休み",
            "fr": "%d jours de pause",
            "de": "%d Tage Pause",
            "es": "%d días de pausa",
            "pt-BR": "%d dias de pausa",
            "it": "%d giorni di pausa",
            "nl": "%d dagen pauze",
            "ko": "%d일 쉼",
            "zh-Hans": "休%d天",
            "ar": "%d أيام راحة",
            "pl": "%d dni przerwy",
            "cs": "%d dní pauzy",
        ]
        for language in Self.languages {
            let strings = try strings(for: language)
            #expect(
                strings["repeat_summary_holiday_suffix"] == holiday[language],
                "\(language): \(strings["repeat_summary_holiday_suffix"] ?? "nil")"
            )
            #expect(
                strings["repeat_summary_skip_days_fmt"] == skipDays[language],
                "\(language): \(strings["repeat_summary_skip_days_fmt"] ?? "nil")"
            )
        }
    }

    @Test
    func japaneseSkipCopyMatchesTheReviewedWording() throws {
        let strings = try strings(for: "ja")
        #expect(strings["skip_all_button"] == "しばらく鳴らさない")
        #expect(strings["skip_all_title"] == "しばらく鳴らさない")
        #expect(strings["skip_alarms_intent"] == "しばらく鳴らさない")
        #expect(strings["skip_apply"] == "鳴らさない")
        #expect(strings["skip_all_active_fmt"] == "%1$@ まで鳴らさない・%2$d本")
        #expect(strings["skip_row_global_fmt"] == "%@ まで鳴らさない")
        #expect(strings["skip_row_skip_fmt"] == "%@ は鳴らさない")
        #expect(strings["skip_row_undo"] == "元に戻す")
        #expect(strings["skip_row_summary_fmt"] == "%@ は鳴らさない・次は %@")
        #expect(strings["skip_row_summary_no_next_fmt"] == "%@ は鳴らさない")
        #expect(strings["holiday_next_skipped"] == "%@ は鳴らさない")
        #expect(strings["holiday_skip_section_title"] == "鳴らさない日")
        #expect(strings["skip_dates_title"] == "日付を選ぶ")
        #expect(strings["skip_dates_selected"] == "鳴らさない日")
        #expect(strings["skip_dates_empty"] == "鳴らさない日はありません")
        #expect(strings["skip_result_section_title"] == "この先、鳴らない日")
        #expect(strings["skip_result_off"] == "鳴らない")
        #expect(strings["skip_result_on"] == "鳴る")
        #expect(strings["skip_result_picked"] == "選んだ日")
        #expect(strings["skip_result_more"] == "もっと見る")
        #expect(strings["skip_result_remove"] == "外す")
        #expect(strings["repeat_summary_holiday_and_days_fmt"] == "祝日と%d日を除く")
        #expect(strings["repeat_summary_days_only_fmt"] == "%d日を除く")
        #expect(strings["skip_result_footer"] == "鳴る曜日に当たる祝日だけを出しています")
        #expect(strings["skip_row_toast_skipped_fmt"] == "%@ は鳴らしません")
        #expect(strings["skip_row_toast_undone_fmt"] == "%@ は鳴らします")
    }
}
