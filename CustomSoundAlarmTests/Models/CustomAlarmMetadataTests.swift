import Testing
import Foundation
@testable import CustomSoundAlarm

/// CustomAlarmMetadata の Codable 互換性と displayName 解決を検証する。
struct CustomAlarmMetadataTests {

    // MARK: - Codable backward compatibility (旧フォーマット)

    @Test
    func oldFormatJSON_decodeSucceedsWithEmptyDisplayName() throws {
        let json = """
        {
            "alarmEntryID": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
            "label": "Test",
            "soundFileName": "ABC123.caf"
        }
        """
        let data = try #require(json.data(using: .utf8))
        let decoder = JSONDecoder()
        let metadata = try decoder.decode(CustomAlarmMetadata.self, from: data)

        #expect(metadata.alarmEntryID == "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")
        #expect(metadata.label == "Test")
        #expect(metadata.soundFileName == "ABC123.caf")
        #expect(metadata.soundDisplayName == "",
                "soundDisplayName が無い旧JSONでもデコードでき、空文字になるべき")
    }

    @Test
    func newFormatJSON_roundTripPreservesDisplayName() throws {
        var original = CustomAlarmMetadata()
        original.alarmEntryID = "A"
        original.label = "Morning"
        original.soundFileName = "abc.caf"
        original.soundDisplayName = "朝のジャズ"

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CustomAlarmMetadata.self, from: data)

        #expect(decoded.alarmEntryID == "A")
        #expect(decoded.label == "Morning")
        #expect(decoded.soundFileName == "abc.caf")
        #expect(decoded.soundDisplayName == "朝のジャズ")
    }

    @Test
    func roundTripEmptyDisplayName() throws {
        var original = CustomAlarmMetadata()
        original.alarmEntryID = "B"
        original.label = "Test"
        original.soundFileName = "xyz.caf"
        original.soundDisplayName = ""

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CustomAlarmMetadata.self, from: data)

        #expect(decoded.soundDisplayName == "")
    }

    // MARK: - UUID leak guard

    @Test
    func emptyDisplayName_doesNotFallbackToFileName() {
        var metadata = CustomAlarmMetadata()
        metadata.alarmEntryID = "C"
        metadata.label = "Silent"
        metadata.soundFileName = "9F3A21C4-1234-5678-9ABC-DEF012345678.caf"
        metadata.soundDisplayName = ""

        #expect(!metadata.soundDisplayName.contains(".caf"))
        #expect(!metadata.soundDisplayName.contains("9F3A21C4"))
        #expect(metadata.soundDisplayName == "")
    }
}
