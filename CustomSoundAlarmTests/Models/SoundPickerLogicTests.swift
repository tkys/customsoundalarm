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
}
