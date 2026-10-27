import Testing
import Foundation
@testable import CustomSoundAlarm

/// 寝過ごし防止の説明（ⓘ）の文言が ja/en の両方にあること
struct BackupInfoCopyTests {

    @Test
    func infoKeysExistInBothLanguages() throws {
        let keys = [
            "backup_alarm_info_mechanism",
            "backup_alarm_info_louder",
            "backup_alarm_info_volume",
            "backup_alarm_early_access_note"
        ]
        for language in ["en", "ja"] {
            let path = try #require(
                Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language)
            )
            let strings = try #require(NSDictionary(contentsOfFile: path) as? [String: String])
            for key in keys {
                #expect(!(strings[key] ?? "").isEmpty, "\(language) \(key)")
            }
        }
    }

    @Test
    func copyMakesNoAbsoluteOrFreeClaims() throws {
        for language in ["en", "ja"] {
            let path = try #require(
                Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language)
            )
            let strings = try #require(NSDictionary(contentsOfFile: path) as? [String: String])
            for key in ["backup_alarm_info_louder", "backup_alarm_info_volume"] {
                let text = (strings[key] ?? "").lowercased()
                for banned in ["必ず", "絶対", "無料", "always", "guarantee", "free"] {
                    #expect(!text.contains(banned), "\(language) \(key) contains \(banned)")
                }
            }
        }
    }
}
