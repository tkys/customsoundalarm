import Testing
import SwiftUI
@testable import CustomSoundAlarm

/// 端末の外観（#291）の値変換を検証する。
struct AnalyticsAppearanceTests {

    @Test
    func colorSchemeMapsToAppearance() {
        #expect(AnalyticsAppearance(colorScheme: .light) == .light)
        #expect(AnalyticsAppearance(colorScheme: .dark) == .dark)
    }

    @Test
    func rawValuesMatchPostHogContract() {
        #expect(AnalyticsAppearance.light.rawValue == "light")
        #expect(AnalyticsAppearance.dark.rawValue == "dark")
        #expect(AnalyticsAppearance.allCases.count == 2)
    }

    @Test
    func superPropertiesUsesUIAppearanceKey() {
        #expect(AnalyticsAppearance.light.superProperties["ui_appearance"] as? String == "light")
        #expect(AnalyticsAppearance.dark.superProperties["ui_appearance"] as? String == "dark")
        #expect(AnalyticsAppearance.dark.superProperties.count == 1)
    }
}
