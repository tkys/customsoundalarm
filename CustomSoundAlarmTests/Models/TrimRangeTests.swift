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

    // MARK: - movingRange（選択範囲全体の平行移動）

    @Test
    func movingRange_positiveDelta_preservesWidth() {
        let r = TrimRange(start: 0, end: 30, duration: 120)
        let moved = r.movingRange(by: 60)
        #expect(moved.start == 60)
        #expect(moved.end == 90)
        #expect(moved.width == 30)
    }

    @Test
    func movingRange_negativeDelta_preservesWidth() {
        let r = TrimRange(start: 100, end: 120, duration: 120)
        let moved = r.movingRange(by: -50)
        #expect(moved.start == 50)
        #expect(moved.end == 70)
        #expect(moved.width == 20)
    }

    @Test
    func movingRange_clampsAtZero() {
        // start=20, end=40, duration=120 → -30 → start<0 → start=0, end=20
        let r = TrimRange(start: 20, end: 40, duration: 120)
        let moved = r.movingRange(by: -30)
        #expect(moved.start == 0)
        #expect(moved.end == 20)
        #expect(moved.width == 20)
    }

    @Test
    func movingRange_clampsAtDuration() {
        // start=100, end=120, duration=120 → +10 → end>120 → end=120, start=100
        let r = TrimRange(start: 100, end: 120, duration: 120)
        let moved = r.movingRange(by: 10)
        #expect(moved.start == 100)
        #expect(moved.end == 120)
        #expect(moved.width == 20)
    }

    @Test
    func movingRange_zeroDelta_isNoop() {
        let r = TrimRange(start: 30, end: 50, duration: 120)
        let moved = r.movingRange(by: 0)
        #expect(moved == r)
    }

    @Test
    func movingRange_shortVideo_allowsFullPan() {
        // 10秒動画 → 全範囲 (0, 10)。移動しても範囲は (0, 10) のまま。
        let r = TrimRange(start: 0, end: 10, duration: 10)
        let moved = r.movingRange(by: 5)
        #expect(moved.start == 0)
        #expect(moved.end == 10)
        #expect(moved.width == 10)
    }

    @Test
    func movingRange_fullWidth_doesNotMove() {
        // 幅 == duration の異常状態 → 移動しない
        let r = TrimRange(start: 0, end: 120, duration: 120)
        let moved = r.movingRange(by: 10)
        #expect(moved.start == 0)
        #expect(moved.end == 120)
    }

    @Test
    func movingRange_midVideo_canSelectLaterPortion() {
        // 5分動画(300秒)で 2:00-2:30 → +60秒 → 3:00-3:30
        let r = TrimRange(start: 120, end: 150, duration: 300)
        let moved = r.movingRange(by: 60)
        #expect(moved.start == 180)
        #expect(moved.end == 210)
        #expect(moved.width == 30)
    }

    @Test
    func movingRange_onInvalidDuration_isNoop() {
        let r = TrimRange(start: 0, end: 0, duration: 0)
        let moved = r.movingRange(by: 10)
        #expect(moved.start == 0)
        #expect(moved.end == 0)
    }

    @Test
    func movingRange_thenResize_stillWorks() {
        // 平行移動後にハンドルでリサイズ
        var r = TrimRange(start: 0, end: 30, duration: 120)
        r = r.movingRange(by: 60)    // (60, 90)
        #expect(r.start == 60 && r.end == 90)
        r = r.movingEnd(to: 100)      // (60, 100) → width=40 > 30 → clamp (60, 90)
        #expect(r.end == 90)
        r = r.movingStart(to: 70)     // (70, 90) → width=20 ≤ 30
        #expect(r.start == 70)
        #expect(r.end == 90)
    }

    // MARK: - パン累積バグの回帰テスト（#36 review）

    /// パンは「固定した基準範囲に対して translation（累積移動量）を適用」する必要がある。
    /// `onChanged` で毎回 `currentRange` に translation を足すと、
    /// 既に動いた位置に累積量が足され二次関数的に加速する。
    /// このテストは固定基準に異なる delta を順に適用し、線形に動くことを検証する。

    @Test
    func panAppliedToFixedBase_isLinear() {
        let base = TrimRange(start: 0, end: 30, duration: 120)

        // delta = 10, 20, 30 を固定基準に適用 → 常に (delta, delta+30)
        let r10 = base.movingRange(by: 10)
        #expect(r10.start == 10 && r10.end == 40)

        let r20 = base.movingRange(by: 20)
        #expect(r20.start == 20 && r20.end == 50)

        let r30 = base.movingRange(by: 30)
        #expect(r30.start == 30 && r30.end == 60)
    }

    @Test
    func panFixedBase_doesNotCompound() {
        // 修正後の正しい挙動: 固定 base に delta を順に適用
        let base = TrimRange(start: 0, end: 30, duration: 120)

        let r1 = base.movingRange(by: 10)
        let r2 = base.movingRange(by: 20)
        let r3 = base.movingRange(by: 30)

        // 線形に動く: (10,40) → (20,50) → (30,60)
        // 累積バグなら: (10,40) → (30,60) → (60,90) となる
        #expect(r1.start == 10)
        #expect(r2.start == 20)  // ← 30 ではない
        #expect(r3.start == 30)  // ← 60 ではない
    }
}
