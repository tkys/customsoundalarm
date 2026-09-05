import Testing
import Foundation
@testable import CustomSoundAlarm

/// `SoundPickerLogic` の純粋関数を検証する。
struct SoundPickerLogicTests {

    // MARK: - presetExpandedDefault

    @Test
    func presetExpanded_noImportedNoOverride_isTrue() {
        // 自分の音が0件 → 開く（受け皿として見せる）
        let result = SoundPickerLogic.presetExpandedDefault(importedCount: 0, userOverride: nil)
        #expect(result == true)
    }

    @Test
    func presetExpanded_hasImportedNoOverride_isFalse() {
        // 自分の音が1件以上 → 畳む
        let result = SoundPickerLogic.presetExpandedDefault(importedCount: 1, userOverride: nil)
        #expect(result == false)
    }

    @Test
    func presetExpanded_hasManyImportedNoOverride_isFalse() {
        let result = SoundPickerLogic.presetExpandedDefault(importedCount: 5, userOverride: nil)
        #expect(result == false)
    }

    @Test
    func presetExpanded_userOverrideTrue_respectsOverride() {
        // ユーザーが手動で開いた場合は、自分の音があっても開く
        let result = SoundPickerLogic.presetExpandedDefault(importedCount: 3, userOverride: true)
        #expect(result == true)
    }

    @Test
    func presetExpanded_userOverrideFalse_respectsOverride() {
        // ユーザーが手動で畳んだ場合は、自分の音が0件でも畳む
        let result = SoundPickerLogic.presetExpandedDefault(importedCount: 0, userOverride: false)
        #expect(result == false)
    }

    // MARK: - shouldShowRecent

    @Test
    func shouldShowRecent_noRecent_returnsFalse() {
        let result = SoundPickerLogic.shouldShowRecent(recentCount: 0, importedCount: 5)
        #expect(result == false)
    }

    @Test
    func shouldShowRecent_hasRecentFewImported_returnsFalse() {
        // 自分の音が少ないときは最近使ったを表示しない（重複して冗長になるため）
        let result = SoundPickerLogic.shouldShowRecent(recentCount: 3, importedCount: 2)
        #expect(result == false)
    }

    @Test
    func shouldShowRecent_hasRecentManyImported_returnsTrue() {
        // 自分の音が多いときは最近使ったを表示する
        let result = SoundPickerLogic.shouldShowRecent(recentCount: 3, importedCount: 5)
        #expect(result == true)
    }

    @Test
    func shouldShowRecent_exactlyAtThreshold_returnsTrue() {
        // threshold ちょうど（既定3）で表示
        let result = SoundPickerLogic.shouldShowRecent(recentCount: 2, importedCount: 3)
        #expect(result == true)
    }

    @Test
    func shouldShowRecent_belowThreshold_returnsFalse() {
        let result = SoundPickerLogic.shouldShowRecent(recentCount: 2, importedCount: 2)
        #expect(result == false)
    }

    @Test
    func shouldShowRecent_customThreshold() {
        let result = SoundPickerLogic.shouldShowRecent(recentCount: 1, importedCount: 2, threshold: 2)
        #expect(result == true)
    }

    @Test
    func shouldShowRecent_hasRecentNoImported_returnsFalse() {
        // 自分の音が0件でも最近使ったに何かあれば... いや、自分の音0件なら表示しない
        let result = SoundPickerLogic.shouldShowRecent(recentCount: 3, importedCount: 0)
        #expect(result == false)
    }

    // MARK: - mySounds（#85: 使用済みでも My Sounds から消さない）

    /// #85 の再現シナリオ: 音源1本を使用（＝Recent 対象）しても My Sounds に出る。
    /// 保有1本では Recent が非表示（閾値未満）なので、ここから消えると完全に不可視になる
    @Test
    func mySounds_singleUsedSound_stillListed() {
        let only = AlarmSound(name: "My Clip", fileName: "clip.caf")
        let mySounds = SoundPickerLogic.mySounds(in: [only])

        // Recent は非表示（保有1本 < 閾値3）
        #expect(SoundPickerLogic.shouldShowRecent(recentCount: 1, importedCount: 1) == false)
        // それでも My Sounds には出る（旧実装は Recent 除外でここからも消えていた）
        #expect(mySounds.count == 1)
        #expect(mySounds.first?.fileName == "clip.caf")
    }

    /// 音源2本・うち1本使用のケースでも両方 My Sounds に出る
    @Test
    func mySounds_twoSoundsOneUsed_bothListed() {
        let used = AlarmSound(name: "Used", fileName: "used.caf")
        let unused = AlarmSound(name: "Unused", fileName: "unused.caf")
        let mySounds = SoundPickerLogic.mySounds(in: [used, unused])

        #expect(SoundPickerLogic.shouldShowRecent(recentCount: 1, importedCount: 2) == false)
        #expect(mySounds.count == 2)
        #expect(mySounds.map(\.fileName).contains("used.caf"))
        #expect(mySounds.map(\.fileName).contains("unused.caf"))
    }

    /// Recent と My Sounds に同じ音源が出ることを許容する（重複は自然・#85）
    @Test
    func mySounds_overlapWithRecent_isAllowed() {
        let a = AlarmSound(name: "A", fileName: "a.caf")
        let b = AlarmSound(name: "B", fileName: "b.caf")
        let c = AlarmSound(name: "C", fileName: "c.caf")
        let mySounds = SoundPickerLogic.mySounds(in: [a, b, c])

        // 保有3本・使用済み2本 → Recent は表示される
        #expect(SoundPickerLogic.shouldShowRecent(recentCount: 2, importedCount: 3) == true)
        // 使用済みの2本（a, b）も My Sounds に残る（= Recent と重複して表示される）
        #expect(mySounds.count == 3)
        #expect(mySounds.map(\.fileName) == ["a.caf", "b.caf", "c.caf"])
    }

    /// プリセットは My Sounds に含めない（従来どおり）
    @Test
    func mySounds_excludesPresets() {
        let preset = AlarmSound(name: "Preset", fileName: "preset.caf", isPreset: true)
        let mine = AlarmSound(name: "Mine", fileName: "mine.caf")
        let mySounds = SoundPickerLogic.mySounds(in: [preset, mine])

        #expect(mySounds.count == 1)
        #expect(mySounds.first?.fileName == "mine.caf")
    }

    /// 空のときは空（空状態ビューの条件）
    @Test
    func mySounds_empty_returnsEmpty() {
        #expect(SoundPickerLogic.mySounds(in: []).isEmpty)
    }

    // MARK: - presetSounds（#85 レビュー: プリセットも同じ規則に従う）

    /// プリセットを1つ使用した後も preset セクションに出る
    @Test
    func presetSounds_usedPreset_stillListed() {
        let used = AlarmSound(name: "Chime", fileName: "chime.caf", isPreset: true)
        let untouched = AlarmSound(name: "Bell", fileName: "bell.caf", isPreset: true)
        let presets = SoundPickerLogic.presetSounds(in: [used, untouched])

        #expect(presets.count == 2)
        #expect(presets.map(\.fileName).contains("chime.caf"))
        #expect(presets.map(\.fileName).contains("bell.caf"))
    }

    /// #85 レビューの再現シナリオ: インポート音源0本・プリセット使用。
    /// importedCount = 0 では Recent が必ず非表示になるため、
    /// 除外していた使ったプリセットはどこにも出なかった
    @Test
    func presetSounds_usedPresetWithNoImports_recentHidden_stillListed() {
        let usedPreset = AlarmSound(name: "Chime", fileName: "chime.caf", isPreset: true)

        // インポート音源0本 → Recent は表示されない
        #expect(SoundPickerLogic.shouldShowRecent(recentCount: 1, importedCount: 0) == false)

        // それでも preset セクションには出る
        let presets = SoundPickerLogic.presetSounds(in: [usedPreset])
        #expect(presets.count == 1)
        #expect(presets.first?.fileName == "chime.caf")
    }

    /// presetSounds は非プリセットを含めない
    @Test
    func presetSounds_excludesNonPresets() {
        let preset = AlarmSound(name: "Preset", fileName: "preset.caf", isPreset: true)
        let mine = AlarmSound(name: "Mine", fileName: "mine.caf")
        let presets = SoundPickerLogic.presetSounds(in: [preset, mine])

        #expect(presets.count == 1)
        #expect(presets.first?.fileName == "preset.caf")
    }

    /// 両セクションが同じ規則（所有する音源の完全な一覧・Recent で除外しない）に従うこと:
    /// 全音源は mySounds と presetSounds に過不足なく分割され、和集合は元の完全な一覧
    @Test
    func mySoundsAndPresetSounds_partitionCompleteList() {
        let sounds = [
            AlarmSound(name: "P1", fileName: "p1.caf", isPreset: true),
            AlarmSound(name: "P2", fileName: "p2.caf", isPreset: true),
            AlarmSound(name: "M1", fileName: "m1.caf"),
            AlarmSound(name: "M2", fileName: "m2.caf"),
            AlarmSound(name: "M3", fileName: "m3.caf"),
        ]

        let my = SoundPickerLogic.mySounds(in: sounds)
        let presets = SoundPickerLogic.presetSounds(in: sounds)

        // 和集合 = 完全な一覧（使用済みかどうかに関係なく全てがどちらかに出る）
        #expect(my.count + presets.count == sounds.count)
        #expect(Set(my.map(\.fileName)).union(presets.map(\.fileName)) == Set(sounds.map(\.fileName)))
        // 積集合なし（二重採番なし）
        #expect(Set(my.map(\.fileName)).isDisjoint(with: presets.map(\.fileName)))
    }
}
