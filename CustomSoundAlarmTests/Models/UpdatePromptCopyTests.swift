import Testing
import Foundation
@testable import CustomSoundAlarm

/// アップデート案内の文言（2026-11-01）。
/// 必須アップデートは不具合以外の理由でも出すため、「問題が見つかった」とは書かない。
struct UpdatePromptCopyTests {

    @Test
    func requiredMessageDoesNotClaimAProblem() throws {
        for language in ["en", "ja"] {
            let path = try #require(
                Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language)
            )
            let strings = try #require(NSDictionary(contentsOfFile: path) as? [String: String])
            let message = try #require(strings["update_required_message"]).lowercased()
            #expect(!message.isEmpty)
            for banned in ["問題", "不具合", "problem", "bug", "issue"] {
                #expect(!message.contains(banned), "\(language): \(banned)")
            }
        }
    }
}
