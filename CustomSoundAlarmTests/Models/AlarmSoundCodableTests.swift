import Testing
import Foundation
@testable import CustomSoundAlarm

/// `AlarmSound` の Codable 移行の罠（#17 罠1）を検証する。
/// `durationSeconds` 追加後に、既存ユーザーの保存済みデータ（キーなし）が
/// 欠落キーで破棄されず、既存フィールドが保持され、`durationSeconds == nil` で
/// 安全にデコードされることを担保する。
struct AlarmSoundCodableTests {

    /// 既存ユーザーデータを模した JSON（durationSeconds キーなし）
    private let legacyJSON = """
    {
      "id": "00000000-0000-0000-0000-000000000001",
      "name": "My Rington",
      "fileName": "ABCDEF-CAF.caf",
      "createdAt": 600000000.0,
      "isPreset": false
    }
    """

    @Test
    func legacyJSONWithoutDuration_decodesWithNilAndKeepsFields() throws {
        let data = try #require(legacyJSON.data(using: .utf8))
        let sound = try JSONDecoder().decode(AlarmSound.self, from: data)

        // 既存フィールドは保持される
        #expect(sound.name == "My Rington")
        #expect(sound.fileName == "ABCDEF-CAF.caf")
        #expect(sound.isPreset == false)
        // 追加フィールドは nil として扱われ、データが消えない
        #expect(sound.durationSeconds == nil)
    }

    @Test
    func legacyArrayWithoutDuration_decodesAllEntries() throws {
        let data = try #require("""
        [
          { "id": "00000000-0000-0000-0000-000000000001", "name": "A", "fileName": "a.caf", "createdAt": 1.0, "isPreset": false },
          { "id": "00000000-0000-0000-0000-000000000002", "name": "B", "fileName": "b.caf", "createdAt": 2.0, "isPreset": true }
        ]
        """.data(using: .utf8))
        let sounds = try JSONDecoder().decode([AlarmSound].self, from: data)

        #expect(sounds.count == 2)
        #expect(sounds[0].durationSeconds == nil)
        #expect(sounds[1].isPreset == true)
    }

    @Test
    func roundTripWithDuration_preservesSeconds() throws {
        var sound = AlarmSound(name: "Audio", fileName: "abc.caf")
        sound.durationSeconds = 42.5

        let data = try JSONEncoder().encode(sound)
        let decoded = try JSONDecoder().decode(AlarmSound.self, from: data)

        #expect(decoded.durationSeconds != nil)
        if let seconds = decoded.durationSeconds {
            // 浮動小数点は許容誤差で比較（#61）
            #expect(abs(seconds - 42.5) < 0.0001)
        }
        #expect(decoded.name == "Audio")
    }

    @Test
    func roundTripWithoutDuration_remainsNil() throws {
        let sound = AlarmSound(name: "P", fileName: "p.caf", isPreset: true)

        let data = try JSONEncoder().encode(sound)
        let decoded = try JSONDecoder().decode(AlarmSound.self, from: data)

        #expect(decoded.durationSeconds == nil)
        #expect(decoded.isPreset == true)
    }

    @Test
    func defaultDurationIsNil() {
        let sound = AlarmSound(name: "D", fileName: "d.caf")
        #expect(sound.durationSeconds == nil)
    }
}