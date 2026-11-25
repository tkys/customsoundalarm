import Testing
import Foundation
@testable import CustomSoundAlarm

/// 寝過ごし防止の説明（ⓘ）と、その時刻の図（#290）の文言が全言語にあること
struct BackupInfoCopyTests {

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
            )
        )
        return try #require(NSDictionary(contentsOfFile: path) as? [String: String])
    }

    @Test
    func infoKeysExistInEveryLanguage() throws {
        let keys = [
            "backup_alarm_info_title",
            "backup_alarm_info_volume",
            "backup_alarm_info_accessibility",
            "backup_alarm_summary_fmt",
            "backup_try",
            "test_ring_status_alarms_off"
        ]
        for language in Self.languages {
            let localized = try strings(for: language)
            for key in keys {
                #expect(!(localized[key] ?? "").isEmpty, "\(language) \(key)")
            }
        }
    }

    /// #290: 使わなくなった長い説明・図のキーを残さない（13言語とも）。
    @Test
    func replacedCopyKeysAreGone() throws {
        let removed = [
            "backup_alarm_info_mechanism",
            "backup_alarm_info_louder",
            "backup_alarm_description_fmt",
            "backup_alarm_timeline_louder",
            "test_ring_backup_title"
        ]
        for language in Self.languages {
            let localized = try strings(for: language)
            for key in removed {
                #expect(localized[key] == nil, "\(language) に \(key) が残っている")
            }
        }
    }

    @Test
    func copyMakesNoAbsoluteOrFreeClaims() throws {
        for language in Self.languages {
            let localized = try strings(for: language)
            for key in [
                "backup_alarm_info_volume",
                "backup_alarm_summary_fmt",
                "backup_try",
                "test_ring_status_alarms_off"
            ] {
                let text = (localized[key] ?? "").lowercased()
                for banned in ["必ず", "絶対", "無料", "always", "guarantee", "free"] {
                    #expect(!text.contains(banned), "\(language) \(key) contains \(banned)")
                }
            }
        }
    }
}
