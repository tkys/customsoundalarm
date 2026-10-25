import Testing
import Foundation
@testable import CustomSoundAlarm

struct VolumeGuideLogicTests {

    @Test
    func imageName_japanese() {
        #expect(VolumeGuideImage.imageName(forLanguageCode: "ja") == "volume_guide_ja")
        #expect(VolumeGuideImage.imageName(forLanguageCode: "JA") == "volume_guide_ja")
        #expect(VolumeGuideImage.imageName(forLanguageCode: "ja-JP") == "volume_guide_ja")
        #expect(VolumeGuideImage.imageName(for: Locale(identifier: "ja_JP")) == "volume_guide_ja")
    }

    @Test
    func imageName_nonJapanese() {
        #expect(VolumeGuideImage.imageName(forLanguageCode: "en") == "volume_guide_en")
        #expect(VolumeGuideImage.imageName(forLanguageCode: "fr") == "volume_guide_en")
        #expect(VolumeGuideImage.imageName(forLanguageCode: nil) == "volume_guide_en")
        #expect(VolumeGuideImage.imageName(for: Locale(identifier: "en_US")) == "volume_guide_en")
    }

    @Test
    func localizationKeysExistInBothLanguages() throws {
        let keys = [
            "volume_guide_title",
            "volume_guide_step1",
            "volume_guide_step2",
            "volume_guide_image_label",
            "volume_guide_warning"
        ]
        for language in ["en", "ja"] {
            let path = try #require(
                Bundle.main.path(
                    forResource: "Localizable",
                    ofType: "strings",
                    inDirectory: nil,
                    forLocalization: language
                )
            )
            let strings = try #require(NSDictionary(contentsOfFile: path) as? [String: String])
            for key in keys {
                #expect(!(strings[key] ?? "").isEmpty, "\(language) \(key)")
            }
        }
    }

    @Test
    func sourceRawValues() {
        #expect(VolumeGuideSource.testRing.rawValue == "test_ring")
    }
}
