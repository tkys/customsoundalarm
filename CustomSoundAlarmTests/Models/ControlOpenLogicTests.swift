import Testing
import Foundation
@testable import CustomSoundAlarm

/// コントロールセンターからの起動（#272）。
struct ControlOpenLogicTests {

    @Test
    func destinationWhileOnboardingIsOnboarding() {
        #expect(
            ControlOpenLogic.destination(kind: .list, isOnboardingVisible: true)
                == .onboarding
        )
        #expect(
            ControlOpenLogic.destination(kind: .add, isOnboardingVisible: true)
                == .onboarding
        )
    }

    @Test
    func destinationAfterOnboardingIsListOrAdd() {
        #expect(
            ControlOpenLogic.destination(kind: .list, isOnboardingVisible: false)
                == .list
        )
        #expect(
            ControlOpenLogic.destination(kind: .add, isOnboardingVisible: false)
                == .add
        )
    }

    @Test
    func controlLabelsExistInAll13Languages() throws {
        let widgetURL = Bundle.main.bundleURL
            .appendingPathComponent("PlugIns/CustomSoundAlarmWidget.appex")
        let widgetBundle = try #require(Bundle(url: widgetURL))
        let languages = [
            "en", "ja", "ar", "cs", "de", "es", "fr", "it", "ko", "nl", "pl",
            "pt-BR", "zh-Hans"
        ]
        for language in languages {
            let path = try #require(
                widgetBundle.path(
                    forResource: "Localizable",
                    ofType: "strings",
                    inDirectory: nil,
                    forLocalization: language
                ),
                "missing widget Localizable.strings for \(language)"
            )
            let strings = try #require(
                NSDictionary(contentsOfFile: path) as? [String: String]
            )
            #expect(!(strings["control_open_list"] ?? "").isEmpty, "\(language) control_open_list")
            #expect(!(strings["add_alarm"] ?? "").isEmpty, "\(language) add_alarm")
        }
    }
}
