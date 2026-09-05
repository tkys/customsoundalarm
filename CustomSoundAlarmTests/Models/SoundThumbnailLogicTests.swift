import Testing
import Foundation
@testable import CustomSoundAlarm

/// 音源サムネイルの選択ロジック（#86）を検証する。
/// 優先順位（動画フレーム > アートワーク > プリセットアイコン > 波形）と
/// フレーム候補から最良の1枚を選ぶ判定が本体。
/// （SoundStore.presetDefinitions が MainActor のため全体を MainActor に置く）
@MainActor
struct SoundThumbnailLogicTests {

    private func approx(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 0.0001
    }

    // MARK: - 表示来源の優先順位

    @Test
    func preferredSource_video_isFirstPriority() {
        // 動画はアートワークが有ってもフレームが最優先
        #expect(SoundThumbnailLogic.preferredSource(isPreset: false, isVideo: true, hasArtwork: true) == .videoFrame)
        #expect(SoundThumbnailLogic.preferredSource(isPreset: false, isVideo: true, hasArtwork: false) == .videoFrame)
    }

    @Test
    func preferredSource_artwork_whenNotVideo() {
        #expect(SoundThumbnailLogic.preferredSource(isPreset: false, isVideo: false, hasArtwork: true) == .artwork)
    }

    @Test
    func preferredSource_preset_overridesEverything() {
        // プリセットは固定アイコンが最優先（動画/アートワークの引数は無視される）
        #expect(SoundThumbnailLogic.preferredSource(isPreset: true, isVideo: true, hasArtwork: true) == .presetIcon)
        #expect(SoundThumbnailLogic.preferredSource(isPreset: true, isVideo: false, hasArtwork: false) == .presetIcon)
    }

    @Test
    func preferredSource_waveform_isLastResort() {
        // 素の音声ファイルのみ波形（識別に使えないため最後の手段）
        #expect(SoundThumbnailLogic.preferredSource(isPreset: false, isVideo: false, hasArtwork: false) == .waveform)
    }

    // MARK: - プリセットの固定アイコン

    @Test
    func presetIcon_eachPresetHasDistinctIcon() {
        let icons = SoundStore.presetDefinitions.map {
            SoundThumbnailLogic.presetIconName(fileName: $0.fileName)
        }
        // 全プリセットが空でないアイコンを持ち
        #expect(icons.allSatisfy { !$0.isEmpty })
        // アイコンが重複しない（音源ごとに識別できる）
        #expect(Set(icons).count == icons.count)
    }

    @Test
    func presetIcon_unknownFileName_fallsBackToMusicNote() {
        #expect(SoundThumbnailLogic.presetIconName(fileName: "Unknown.caf") == "music.note")
        #expect(SoundThumbnailLogic.presetIconName(fileName: "") == "music.note")
    }

    // MARK: - 分散計算（輝度の散らばり）

    @Test
    func variance_uniformSamples_isZero() {
        #expect(approx(SoundThumbnailLogic.variance(samples: [0.5, 0.5, 0.5]), 0))
        #expect(approx(SoundThumbnailLogic.variance(samples: [1.0, 1.0]), 0))
    }

    @Test
    func variance_knownValues() {
        // [0, 1]: mean 0.5 → (0.25 + 0.25) / 2 = 0.25
        #expect(approx(SoundThumbnailLogic.variance(samples: [0, 1]), 0.25))
        // [0, 0, 1, 1]: mean 0.5 → 4 * 0.25 / 4 = 0.25
        #expect(approx(SoundThumbnailLogic.variance(samples: [0, 0, 1, 1]), 0.25))
        // [0, 0.5, 1]: mean 0.5 → (0.25 + 0 + 0.25) / 3
        #expect(approx(SoundThumbnailLogic.variance(samples: [0, 0.5, 1]), 1.0 / 6.0))
    }

    @Test
    func variance_emptyOrSingle_isZero() {
        #expect(SoundThumbnailLogic.variance(samples: []) == 0)
        #expect(SoundThumbnailLogic.variance(samples: [0.7]) == 0)
    }

    // MARK: - 最良フレーム選択（#86 の本体）

    /// 全候補の中から輝度分散が最大 = 暗転・無地でない フレームを選ぶ
    @Test
    func bestFrameIndex_picksHighestVariance() {
        // 0番目=暗転(0.01) 1番目=情報量大(5.2) 2番目=中(3.0) → 1
        #expect(SoundThumbnailLogic.bestFrameIndex(variances: [0.01, 5.2, 3.0]) == 1)
    }

    @Test
    func bestFrameIndex_prefersNonBlankOverBlack() {
        // 全フレーム暗い中でも最も散らばっているものを選ぶ
        #expect(SoundThumbnailLogic.bestFrameIndex(variances: [0.0, 0.02, 0.0]) == 1)
    }

    @Test
    func bestFrameIndex_empty_returnsNil() {
        #expect(SoundThumbnailLogic.bestFrameIndex(variances: []) == nil)
    }

    @Test
    func bestFrameIndex_tie_picksFirst() {
        #expect(SoundThumbnailLogic.bestFrameIndex(variances: [3.0, 3.0, 1.0]) == 0)
    }

    @Test
    func bestFrameIndex_singleCandidate() {
        #expect(SoundThumbnailLogic.bestFrameIndex(variances: [0.5]) == 0)
    }

    // MARK: - AlarmSound のサムネイルフィールド（Codable 後方互換）

    /// #17 罠1 / #68 の教訓: 追加フィールドは Optional。
    /// サムネイルキーを欠く既存データ（旧バージョンで保存）が nil として復元されること
    @Test
    func alarmSound_decodesWithoutThumbnailKey() throws {
        let json = """
        {"id":"61A5C1A0-0000-0000-0000-000000000001",
         "name":"Old Clip",
         "fileName":"old.caf",
         "createdAt":700000000,
         "isPreset":false,
         "durationSeconds":12.5}
        """
        let decoded = try JSONDecoder().decode(AlarmSound.self, from: Data(json.utf8))
        #expect(decoded.thumbnailFileName == nil)
        #expect(decoded.name == "Old Clip")
    }

    @Test
    func alarmSound_roundTripsThumbnailFileName() throws {
        let original = AlarmSound(name: "Clip", fileName: "a.caf", thumbnailFileName: "thumb.jpg")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AlarmSound.self, from: data)
        #expect(decoded.thumbnailFileName == "thumb.jpg")
    }
}