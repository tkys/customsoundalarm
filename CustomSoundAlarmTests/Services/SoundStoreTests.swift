import Testing
import Foundation
@testable import CustomSoundAlarm

/// SoundStore.displayName(for:) を検証する。
/// 実ストアの状態に依存せず、一時的に音を追加/削除してテストする。
@MainActor
struct SoundStoreDisplayNameTests {

    private let store = SoundStore.shared

    @Test
    func registeredSound_returnsDisplayName() {
        let testFileName = "__test_display_name__delete_me__.caf"
        let testDisplayName = "Test Sound"

        store.add(AlarmSound(name: testDisplayName, fileName: testFileName, isPreset: false))
        defer {
            if let sound = store.sounds.first(where: { $0.fileName == testFileName }) {
                store.remove(sound)
            }
        }

        #expect(store.displayName(for: testFileName) == testDisplayName)
    }

    @Test
    func unknownFileName_doesNotContainCafOrUuid() {
        let name = store.displayName(for: "9F3A21C4-1234-5678-9ABC-DEF012345678.caf")
        #expect(!name.contains(".caf"), "戻り値に .caf 拡張子が含まれないこと")
        #expect(!name.contains("9F3A21C4"), "戻り値に UUID が含まれないこと")
    }

    @Test
    func unknownFileName_returnsLocalizedFallback() {
        let name = store.displayName(for: "nonexistent_sound_xyz.caf")
        #expect(!name.isEmpty)
        #expect(name != "nonexistent_sound_xyz.caf")
    }

    @Test
    func emptyFileName_returnsEmptyString() {
        #expect(store.displayName(for: "") == "")
    }
}
