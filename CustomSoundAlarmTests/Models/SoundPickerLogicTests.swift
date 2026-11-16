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

    // MARK: - mySounds（#85: 使用済みでも My Sounds から消さない）

    /// #85 の再現シナリオ: 音源1本を使用（＝Recent 対象）しても My Sounds に出る。
    /// 保有1本では Recent が非表示（閾値未満）なので、ここから消えると完全に不可視になる
    @Test
    func mySounds_singleUsedSound_stillListed() {
        let only = AlarmSound(name: "My Clip", fileName: "clip.caf")
        let mySounds = SoundPickerLogic.mySounds(in: [only])

        // Recent は非表示（保有1本 < 閾値3）
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

    // MARK: - 最近使った順（#123）

    @Test
    func mySoundsByRecentUse_ordersRecentFirst() {
        let a = AlarmSound(name: "A", fileName: "a.caf")
        let b = AlarmSound(name: "B", fileName: "b.caf")
        let c = AlarmSound(name: "C", fileName: "c.caf")

        let sorted = SoundPickerLogic.mySoundsByRecentUse(
            in: [a, b, c],
            recentFileNames: ["c.caf", "a.caf"]
        )

        #expect(sorted.map(\.fileName) == ["c.caf", "a.caf", "b.caf"])
    }

    @Test
    func mySoundsByRecentUse_unusedKeepOriginalOrder() {
        let a = AlarmSound(name: "A", fileName: "a.caf")
        let b = AlarmSound(name: "B", fileName: "b.caf")
        let c = AlarmSound(name: "C", fileName: "c.caf")

        let sorted = SoundPickerLogic.mySoundsByRecentUse(
            in: [a, b, c],
            recentFileNames: []
        )

        #expect(sorted.map(\.fileName) == ["a.caf", "b.caf", "c.caf"])
    }

    @Test
    func mySoundsByRecentUse_duplicateNamesDoNotCrash() {
        let a = AlarmSound(name: "A", fileName: "a.caf")
        let b = AlarmSound(name: "B", fileName: "b.caf")

        let sorted = SoundPickerLogic.mySoundsByRecentUse(
            in: [a, b],
            recentFileNames: ["b.caf", "a.caf", "b.caf"]
        )

        #expect(sorted.map(\.fileName) == ["b.caf", "a.caf"])
    }

    @Test
    func mySoundsByRecentUse_excludesPresets() {
        let preset = AlarmSound(name: "Preset", fileName: "p.caf", isPreset: true)
        let mine = AlarmSound(name: "Mine", fileName: "m.caf")

        let sorted = SoundPickerLogic.mySoundsByRecentUse(
            in: [preset, mine],
            recentFileNames: ["p.caf", "m.caf"]
        )

        #expect(sorted.map(\.fileName) == ["m.caf"])
    }

    // MARK: - 行タップの試し聴き（#196）

    private var marimba: AlarmSound {
        AlarmSound(name: "Marimba", fileName: "PresetMarimba.caf", isPreset: true)
    }

    private var bell: AlarmSound {
        AlarmSound(name: "Bell", fileName: "PresetBell.caf", isPreset: true)
    }

    @Test
    func previewTap_stoppedRow_selectsAndPlays() {
        let sound = marimba
        let outcome = SoundPreviewLogic.tap(
            tapped: sound,
            selected: sound,
            playingFileName: nil,
            isActiveSelection: true
        )
        #expect(outcome.plays)
        #expect(outcome.notifiesSelection)
        #expect(!outcome.stops)
        #expect(!outcome.selectionChanged)
    }

    @Test
    func previewTap_otherRowPlaying_switchesAndPlays() {
        let outcome = SoundPreviewLogic.tap(
            tapped: bell,
            selected: marimba,
            playingFileName: marimba.fileName,
            isActiveSelection: false
        )
        #expect(outcome.plays)
        #expect(outcome.notifiesSelection)
        #expect(outcome.selectionChanged)
    }

    @Test
    func previewTap_samePlayingActiveSelection_stops() {
        let outcome = SoundPreviewLogic.tap(
            tapped: marimba,
            selected: marimba,
            playingFileName: marimba.fileName,
            isActiveSelection: true
        )
        #expect(outcome.stops)
        #expect(!outcome.plays)
        #expect(!outcome.notifiesSelection)
        #expect(!outcome.selectionChanged)
    }

    /// プレイリスト選択中は、同じ音が選ばれていても音に切り替える（#196 レビュー）。
    @Test
    func previewTap_playlistSelected_sameSoundSwitchesToSound() {
        let outcome = SoundPreviewLogic.tap(
            tapped: marimba,
            selected: marimba,
            playingFileName: nil,
            isActiveSelection: false
        )
        #expect(outcome.notifiesSelection)
        #expect(outcome.plays)
        #expect(!outcome.stops)
        #expect(outcome.selectionChanged)
    }

    /// 右端の再生ボタンで鳴らしたあと同じ行をタップ → 止めずに選ぶ（#196 レビュー）。
    @Test
    func previewTap_playlistSelectedPlayedByButton_tappingRowSelectsIt() {
        let outcome = SoundPreviewLogic.tap(
            tapped: marimba,
            selected: marimba,
            playingFileName: marimba.fileName,
            isActiveSelection: false
        )
        #expect(outcome.notifiesSelection)
        #expect(outcome.plays)
        #expect(!outcome.stops)
        #expect(outcome.selectionChanged)
    }

    @Test
    func previewTap_defaultRow_selectsOnly() {
        // 既定の音には鳴らすファイルがない。鳴っている音は止める
        let outcome = SoundPreviewLogic.tap(
            tapped: nil,
            selected: marimba,
            playingFileName: marimba.fileName,
            isActiveSelection: false
        )
        #expect(outcome.notifiesSelection)
        #expect(outcome.stops)
        #expect(!outcome.plays)
        #expect(outcome.selectionChanged)
    }

    @Test
    func previewSelectionChanged_sameRow_isFalse() {
        // 再タップで止めるときに sound_selected を二重に送らない
        let sound = marimba
        #expect(!SoundPreviewLogic.selectionChanged(tapped: sound, selected: sound))
        #expect(!SoundPreviewLogic.selectionChanged(tapped: nil, selected: nil))
    }

    @Test
    func previewSelectionChanged_otherRow_isTrue() {
        #expect(SoundPreviewLogic.selectionChanged(tapped: bell, selected: marimba))
        #expect(SoundPreviewLogic.selectionChanged(tapped: nil, selected: marimba))
        #expect(SoundPreviewLogic.selectionChanged(tapped: marimba, selected: nil))
    }

    @Test
    func previewStopsWhenLeaving() {
        // 鳴っているときは、画面を閉じる・保存する・取り込みを始めるときに止める
        #expect(SoundPreviewLogic.shouldStop(playingFileName: marimba.fileName))
        // 鳴っていなければ止める必要はない
        #expect(!SoundPreviewLogic.shouldStop(playingFileName: nil))
    }
}
