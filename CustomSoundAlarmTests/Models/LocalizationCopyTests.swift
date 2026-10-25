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
}
