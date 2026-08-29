import Testing
import Foundation
@testable import CustomSoundAlarm

/// フィルムストリップの生成状態遷移（#88）を検証する。
/// 「生成中」と「0枚で完了」の区別が本Issueの本体。
struct FilmstripLogicTests {

    // MARK: - 初期状態（映像トラックの有無）

    @Test
    func initialState_withVideoTrack_isLoading() {
        #expect(FilmstripLogic.initialState(hasVideoTrack: true) == .loading)
    }

    @Test
    func initialState_withoutVideoTrack_isUnavailable() {
        // 音声のみファイル → スピナーを出さず非表示
        #expect(FilmstripLogic.initialState(hasVideoTrack: false) == .unavailable)
    }

    // MARK: - 生成完了（読み込み中 → 成功）

    @Test
    func finishState_generatedImages_isReady() {
        let state = FilmstripLogic.finishState(generatedCount: 12)
        #expect(state == .ready(count: 12))
        #expect(state != .loading)
    }

    @Test
    func finishState_partialGeneration_isReady() {
        // 一部フレームだけ失敗しても1枚以上あれば表示する（穴が開く程度）
        let state = FilmstripLogic.finishState(generatedCount: 5)
        #expect(state == .ready(count: 5))
    }

    // MARK: - 生成完了（読み込み中 → 0枚・#88 の本体）

    /// 全フレーム生成に失敗した（＝映像トラックが無い素材など）場合:
    /// **0枚で完了した時点でスピナー状態（loading）が解除されること**
    @Test
    func finishState_zeroImages_clearsSpinnerState() {
        let state = FilmstripLogic.finishState(generatedCount: 0)
        #expect(state != .loading)       // スピナーは出続けない
        #expect(state == .unavailable)   // 領域ごと非表示
    }

    // MARK: - 状態遷移の通し（loading → 完了）

    @Test
    func transition_loadingToReady() {
        // 映像あり → 生成 → 12枚
        let afterTrack = FilmstripLogic.initialState(hasVideoTrack: true)
        #expect(afterTrack == .loading)
        let finished = FilmstripLogic.finishState(generatedCount: 12)
        #expect(finished == .ready(count: 12))
    }

    @Test
    func transition_loadingToZero() {
        // 映像ありと判定されても全フレーム失敗しうる → 0枚で非表示に着地
        let afterTrack = FilmstripLogic.initialState(hasVideoTrack: true)
        #expect(afterTrack == .loading)
        let finished = FilmstripLogic.finishState(generatedCount: 0)
        #expect(finished == .unavailable)
        #expect(finished != .loading)
    }

    @Test
    func transition_audioOnly_neverShowsSpinner() {
        // 音声のみ: 初期状態から一貫して unavailable（loading を経由しない）
        let state = FilmstripLogic.initialState(hasVideoTrack: false)
        #expect(state == .unavailable)
        #expect(state != .loading)
    }
}