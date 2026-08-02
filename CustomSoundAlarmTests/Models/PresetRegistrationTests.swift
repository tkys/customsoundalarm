import Testing
import Foundation
@testable import CustomSoundAlarm

/// `PresetRegistration.presetsToRegister` の登録判定を検証する。
/// 罠1（削除済みプリセットの復活防止）と更新時の新規プリセット追加をカバーする。
struct PresetRegistrationTests {

    private let jazz = PresetRegistration.Definition(fileName: "PresetAlarm.caf", labelKey: "preset_jazz")
    private let bell = PresetRegistration.Definition(fileName: "PresetBell.caf", labelKey: "preset_bell")
    private let chime = PresetRegistration.Definition(fileName: "PresetChime.caf", labelKey: "preset_chime")

    // MARK: - 基本パターン

    @Test
    func firstLaunch_registersAllDefinitions() {
        let defs = [jazz, bell]
        let result = PresetRegistration.presetsToRegister(
            definitions: defs,
            existingFileNames: [],
            dismissedFileNames: []
        )
        #expect(result.count == 2)
        #expect(result.map(\.fileName) == ["PresetAlarm.caf", "PresetBell.caf"])
    }

    @Test
    func alreadyRegistered_skipsExisting() {
        let result = PresetRegistration.presetsToRegister(
            definitions: [jazz, bell],
            existingFileNames: ["PresetAlarm.caf"],
            dismissedFileNames: []
        )
        #expect(result.count == 1)
        #expect(result[0].fileName == "PresetBell.caf")
    }

    // MARK: - 罠1: 削除済みは復活しない

    @Test
    func dismissedPreset_notRegistered() {
        let result = PresetRegistration.presetsToRegister(
            definitions: [jazz, bell],
            existingFileNames: [],
            dismissedFileNames: ["PresetAlarm.caf"]
        )
        #expect(result.count == 1)
        #expect(result[0].fileName == "PresetBell.caf")
    }

    @Test
    func allDismissed_returnsEmpty() {
        let result = PresetRegistration.presetsToRegister(
            definitions: [jazz, bell],
            existingFileNames: [],
            dismissedFileNames: ["PresetAlarm.caf", "PresetBell.caf"]
        )
        #expect(result.isEmpty)
    }

    // MARK: - アプリ更新時の新規プリセット追加

    @Test
    func appUpdate_newPresetRegistered_existingPreserved() {
        // 既存: jazz のみ登録済み。bell は定義リストに追加された新規プリセット。
        let result = PresetRegistration.presetsToRegister(
            definitions: [jazz, bell],
            existingFileNames: ["PresetAlarm.caf"],
            dismissedFileNames: []
        )
        #expect(result.count == 1)
        #expect(result[0].fileName == "PresetBell.caf")
    }

    @Test
    func appUpdate_newPresetNotDismissed() {
        // jazz は削除されたが、bell は新規追加。bell は登録される。
        let result = PresetRegistration.presetsToRegister(
            definitions: [jazz, bell, chime],
            existingFileNames: [],
            dismissedFileNames: ["PresetAlarm.caf"]
        )
        #expect(result.count == 2)
        #expect(result.map(\.fileName) == ["PresetBell.caf", "PresetChime.caf"])
    }

    @Test
    func appUpdate_allExistingAndDismissed_returnsEmpty() {
        let result = PresetRegistration.presetsToRegister(
            definitions: [jazz, bell],
            existingFileNames: ["PresetAlarm.caf"],
            dismissedFileNames: ["PresetBell.caf"]
        )
        #expect(result.isEmpty)
    }

    // MARK: - 境界

    @Test
    func emptyDefinitions_returnsEmpty() {
        let result = PresetRegistration.presetsToRegister(
            definitions: [],
            existingFileNames: [],
            dismissedFileNames: []
        )
        #expect(result.isEmpty)
    }

    @Test
    func existingAndDismissedSamePreset_skipsBothWays() {
        // 既に登録済みかつ削除された（通常は起きないが念のため）
        let result = PresetRegistration.presetsToRegister(
            definitions: [jazz],
            existingFileNames: ["PresetAlarm.caf"],
            dismissedFileNames: ["PresetAlarm.caf"]
        )
        #expect(result.isEmpty)
    }
}
