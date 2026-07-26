import Testing
import Foundation
@testable import CustomSoundAlarm

/// `TrimRange` の範囲クランプロジックを検証する。
/// ジェスチャ中に毎回適用される純粋関数として振る舞うことを前提とする。
struct TrimRangeTests {

    // MARK: - 初期化

    @Test
    func init_clampsToDuration() {
        let r = TrimRange(start: -5, end: 100, duration: 60)
        #expect(r.start == 0)
        #expect(r.end == 60)
        #expect(r.duration == 60)
    }

    @Test
    func init_negativeDuration_returnsZeros() {
        let r = TrimRange(start: 10, end: 20, duration: -5)
        #expect(r.start == 0)
        #expect(r.end == 0)
        #expect(r.duration == 0)
        #expect(!r.isValid)
    }

    @Test
    func init_zeroDuration_isInvalid() {
        let r = TrimRange(start: 0, end: 0, duration: 0)
        #expect(!r.isValid)
        #expect(r.width == 0)
    }

    // MARK: - fullRange

    @Test
    func fullRange_shortVideo_selectsAll() {
        // 10秒動画 → 全範囲 (0, 10)
        let r = TrimRange.fullRange(duration: 10)
        #expect(r.start == 0)
        #expect(r.end == 10)
        #expect(r.width == 10)
    }

    @Test
    func fullRange_longVideo_capsAtMaxRange() {
        // 120秒動画 → (0, 30)
        let r = TrimRange.fullRange(duration: 120)
        #expect(r.start == 0)
        #expect(r.end == 30)
        #expect(r.width == 30)
    }

    @Test
    func fullRange_customMaxRange() {
        let r = TrimRange.fullRange(duration: 100, maxRange: 15)
        #expect(r.end == 15)
    }

    // MARK: - movingStart: 基本クランプ

    @Test
    func movingStart_normalRange() {
        let r = TrimRange(start: 10, end: 40, duration: 60)
        let moved = r.movingStart(to: 20)
        #expect(moved.start == 20)
        #expect(moved.end == 40)
    }

    @Test
    func movingStart_clampsBelowZero() {
        let r = TrimRange(start: 5, end: 10, duration: 60)
        let moved = r.movingStart(to: -5)
        #expect(moved.start == 0)
    }

    @Test
    func movingStart_cannotExceedEnd() {
        // start を end(40) より後に動かそうとしても end で止まる
        let r = TrimRange(start: 10, end: 40, duration: 60)
        let moved = r.movingStart(to: 50)
        #expect(moved.start == 40)
        #expect(moved.end == 40)
        #expect(moved.width == 0)
    }

    // MARK: - movingStart: 30秒制限（そこで止める）

    @Test
    func movingStart_30sLimitStopsAtEndMinus30() {
        // end=60, maxRange=30 → start は 30 が下限
        // start を 5 に動かそうとしても 30 で止まる
        let r = TrimRange(start: 35, end: 60, duration: 120)
        let moved = r.movingStart(to: 5)
        #expect(moved.start == 30)
        #expect(moved.end == 60)
        #expect(moved.width == 30)
    }

    @Test
    func movingStart_shortVideoNo30sConstraint() {
        // 10秒動画 → 30秒制限は効かない（全範囲選べる）
        let r = TrimRange(start: 2, end: 10, duration: 10)
        let moved = r.movingStart(to: 0)
        #expect(moved.start == 0)
        #expect(moved.end == 10)
        #expect(moved.width == 10)
    }

    // MARK: - movingEnd: 基本クランプ

    @Test
    func movingEnd_normalRange() {
        let r = TrimRange(start: 10, end: 20, duration: 60)
        let moved = r.movingEnd(to: 25)
        #expect(moved.end == 25)
        #expect(moved.start == 10)
    }

    @Test
    func movingEnd_clampsAboveDuration() {
        let r = TrimRange(start: 50, end: 55, duration: 60)
        let moved = r.movingEnd(to: 100)
        #expect(moved.end == 60)
    }

    @Test
    func movingEnd_cannotGoBelowStart() {
        // end を start(10) より前に動かそうとしても start で止まる
        let r = TrimRange(start: 10, end: 40, duration: 60)
        let moved = r.movingEnd(to: 5)
        #expect(moved.end == 10)
        #expect(moved.width == 0)
    }

    // MARK: - movingEnd: 30秒制限（そこで止める）

    @Test
    func movingEnd_30sLimitStopsAtStartPlus30() {
        // start=0, maxRange=30 → end は 30 が上限
        // end を 50 に動かそうとしても 30 で止まる
        let r = TrimRange(start: 0, end: 20, duration: 120)
        let moved = r.movingEnd(to: 50)
        #expect(moved.end == 30)
        #expect(moved.start == 0)
        #expect(moved.width == 30)
    }

    @Test
    func movingEnd_30sLimitWithOffset() {
        // start=40, maxRange=30 → end は 70 が上限
        let r = TrimRange(start: 40, end: 60, duration: 120)
        let moved = r.movingEnd(to: 100)
        #expect(moved.end == 70)
    }

    // MARK: - 境界・異常系

    @Test
    func movingStart_onInvalidDuration_isNoop() {
        let r = TrimRange(start: 0, end: 0, duration: 0)
        let moved = r.movingStart(to: 10)
        #expect(moved.start == 0)
        #expect(moved.end == 0)
    }

    @Test
    func movingEnd_onInvalidDuration_isNoop() {
        let r = TrimRange(start: 0, end: 0, duration: 0)
        let moved = r.movingEnd(to: 10)
        #expect(moved.end == 0)
    }

    @Test
    func movingStart_exactlyAt30sBoundary() {
        // end=50, start を 20 に動かす → width=30（上限ちょうど）
        let r = TrimRange(start: 25, end: 50, duration: 120)
        let moved = r.movingStart(to: 20)
        #expect(moved.start == 20)
        #expect(moved.width == 30)
    }

    @Test
    func movingEnd_exactlyAt30sBoundary() {
        // start=10, end を 40 に動かす → width=30（上限ちょうど）
        let r = TrimRange(start: 10, end: 30, duration: 120)
        let moved = r.movingEnd(to: 40)
        #expect(moved.end == 40)
        #expect(moved.width == 30)
    }

    // MARK: - 連続操作（ジェスチャ中の複数 onChanged をシミュレート）

    @Test
    func repeatedMovingStart_neverExceeds30s() {
        var r = TrimRange(start: 40, end: 60, duration: 120)
        // ジェスチャ中に start を徐々に下げていく
        for target in stride(from: 35.0, through: 0, by: -5) {
            r = r.movingStart(to: target)
            #expect(r.width <= 30.0, "width should never exceed 30 (target=\(target))")
            #expect(r.end == 60, "end should not move")
        }
        // 最終的に 30 で止まる
        #expect(r.start == 30)
    }

    @Test
    func repeatedMovingEnd_neverExceeds30s() {
        var r = TrimRange(start: 0, end: 20, duration: 120)
        // ジェスチャ中に end を徐々に上げていく
        for target in stride(from: 25.0, through: 100, by: 5) {
            r = r.movingEnd(to: target)
            #expect(r.width <= 30.0, "width should never exceed 30 (target=\(target))")
            #expect(r.start == 0, "start should not move")
        }
        // 最終的に 30 で止まる
        #expect(r.end == 30)
    }

    @Test
    func alternatingMoves_preserve30sCap() {
        var r = TrimRange(start: 10, end: 30, duration: 120)
        r = r.movingStart(to: 20)  // start=20, end=30, width=10
        #expect(r.start == 20)
        r = r.movingEnd(to: 60)    // width=40 にならない、end=50 で止まる
        #expect(r.end == 50)
        #expect(r.width == 30)
        r = r.movingStart(to: 5)   // start は end-30=20 で止まる
        #expect(r.start == 20)
        #expect(r.end == 50)
    }
}
