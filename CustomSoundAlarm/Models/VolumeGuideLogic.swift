import Foundation

/// 音量案内を開いた場所（計測の `from`・#121）
enum VolumeGuideSource: String, Sendable, Equatable {
    case testRing = "test_ring"
    case loudness
}

/// 音量案内の画像選び分け（#121）。
/// 端末の言語が日本語なら ja、それ以外は en。
enum VolumeGuideImage {
    static let japaneseImageName = "volume_guide_ja"
    static let englishImageName = "volume_guide_en"

    static func imageName(forLanguageCode languageCode: String?) -> String {
        guard let languageCode else { return englishImageName }
        let primary = languageCode
            .lowercased()
            .split(separator: "-", maxSplits: 1)
            .first
            .map(String.init)
        return primary == "ja" ? japaneseImageName : englishImageName
    }

    static func imageName(for locale: Locale) -> String {
        imageName(forLanguageCode: locale.language.languageCode?.identifier)
    }
}
