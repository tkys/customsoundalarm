import Testing
import Foundation
@testable import CustomSoundAlarm

/// 波形クロップUI（#77）の純粋関数群のテスト。
/// 座標→時間の変換・ズーム窓の算出と同期・リサンプルを検証する。
/// 浮動小数の比較は abs(x-y) < 0.0001。
struct WaveformCropMathTests {

    private func approx(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 0.0001
    }

    // MARK: - 上段（全体波形）の座標変換

    @Test
    func overviewTime_basics() {
        #expect(WaveformCropMath.overviewTime(atX: 0, width: 300, duration: 600) == 0)
        #expect(approx(WaveformCropMath.overviewTime(atX: 300, width: 300, duration: 600), 600))
        #expect(approx(WaveformCropMath.overviewTime(atX: 150, width: 300, duration: 600), 300))
    }

    @Test
    func overviewTime_clampsOutOfRange() {
        #expect(WaveformCropMath.overviewTime(atX: -10, width: 300, duration: 600) == 0)
        #expect(approx(WaveformCropMath.overviewTime(atX: 500, width: 300, duration: 600), 600))
    }

    @Test
    func overviewTime_zeroWidth_returnsZero() {
        #expect(WaveformCropMath.overviewTime(atX: 100, width: 0, duration: 600) == 0)
        #expect(WaveformCropMath.overviewTime(atX: 100, width: -5, duration: 600) == 0)
    }

    @Test
    func overviewX_roundTrip() {
        let width = 300.0
        let duration = 600.0
        for t in stride(from: 0.0, through: duration, by: 97.3) {
            let x = WaveformCropMath.overviewX(for: t, width: width, duration: duration)
            let back = WaveformCropMath.overviewTime(atX: x, width: width, duration: duration)
            #expect(approx(back, min(max(t, 0), duration)))
        }
    }

    @Test
    func overviewX_clampsTime() {
        #expect(WaveformCropMath.overviewX(for: -10, width: 300, duration: 600) == 0)
        #expect(approx(WaveformCropMath.overviewX(for: 700, width: 300, duration: 600), 300))
    }

    // MARK: - 下段（拡大波形）の座標変換

    @Test
    func zoomTime_basics() {
        let window = CropWindow(start: 100, end: 130)
        #expect(approx(WaveformCropMath.zoomTime(atX: 0, width: 300, window: window), 100))
        #expect(approx(WaveformCropMath.zoomTime(atX: 300, width: 300, window: window), 130))
        #expect(approx(WaveformCropMath.zoomTime(atX: 150, width: 300, window: window), 115))
    }

    @Test
    func zoomTime_clampsX() {
        let window = CropWindow(start: 100, end: 130)
        #expect(approx(WaveformCropMath.zoomTime(atX: -50, width: 300, window: window), 100))
        #expect(approx(WaveformCropMath.zoomTime(atX: 999, width: 300, window: window), 130))
    }

    @Test
    func zoomX_clampsTimeIntoWindow() {
        let window = CropWindow(start: 100, end: 130)
        #expect(approx(WaveformCropMath.zoomX(for: 90, width: 300, window: window), 0))
        #expect(approx(WaveformCropMath.zoomX(for: 115, width: 300, window: window), 150))
        #expect(approx(WaveformCropMath.zoomX(for: 140, width: 300, window: window), 300))
    }

    @Test
    func zoom_roundTrip_precision() {
        // #76: 600秒ファイルでも下段なら高精度。窓30秒・幅300ptで 1pt = 0.1秒
        let window = CropWindow(start: 300, end: 330)
        let width = 300.0
        for x in stride(from: 0.0, through: width, by: 37.5) {
            let t = WaveformCropMath.zoomTime(atX: x, width: width, window: window)
            let back = WaveformCropMath.zoomX(for: t, width: width, window: window)
            #expect(approx(back, x))
        }
    }

    // MARK: - ズーム窓の算出

    @Test
    func zoomWindow_centeredOnSelection() {
        // 選択 30-40（幅10）→ 希望幅30 → 中心35 → (20, 50)
        let range = TrimRange(start: 30, end: 40, duration: 600, maxRange: 600)
        let window = WaveformCropMath.zoomWindow(range: range, duration: 600)
        #expect(approx(window.start, 20))
        #expect(approx(window.end, 50))
    }

    @Test
    func zoomWindow_minimumWindow() {
        // 選択幅が小さくても最低8秒の窓
        let range = TrimRange(start: 100, end: 102, duration: 600, maxRange: 600)
        let window = WaveformCropMath.zoomWindow(range: range, duration: 600)
        #expect(approx(window.start, 97))
        #expect(approx(window.end, 105))
    }

    @Test
    func zoomWindow_clampsAtStart() {
        let range = TrimRange(start: 0, end: 2, duration: 600, maxRange: 600)
        let window = WaveformCropMath.zoomWindow(range: range, duration: 600)
        #expect(approx(window.start, 0))
        #expect(approx(window.end, 8))
    }

    @Test
    func zoomWindow_clampsAtEnd() {
        let range = TrimRange(start: 595, end: 597, duration: 600, maxRange: 600)
        let window = WaveformCropMath.zoomWindow(range: range, duration: 600)
        #expect(approx(window.end, 600))
        #expect(approx(window.start, 592))
    }

    @Test
    func zoomWindow_capsAt60Seconds() {
        // 選択幅30 → 3倍で90だが上限60
        let range = TrimRange(start: 100, end: 130, duration: 600, maxRange: 600)
        let window = WaveformCropMath.zoomWindow(range: range, duration: 600)
        #expect(approx(window.width, 60))
        #expect(approx(window.start, 85))
        #expect(approx(window.end, 145))
    }

    @Test
    func zoomWindow_shortFile_shrinksToDuration() {
        let range = TrimRange(start: 0, end: 20, duration: 20, maxRange: 600)
        let window = WaveformCropMath.zoomWindow(range: range, duration: 20)
        #expect(approx(window.start, 0))
        #expect(approx(window.end, 20))
    }

    @Test
    func zoomWindow_invalidDuration_returnsZeroWindow() {
        let range = TrimRange(start: 0, end: 0, duration: 0, maxRange: 600)
        let window = WaveformCropMath.zoomWindow(range: range, duration: 0)
        #expect(window.start == 0 && window.end == 0)
    }

    // MARK: - ズーム窓の同期

    @Test
    func syncedWindow_keepsWindowWhenSelectionInsideMargin() {
        // 窓(20,50)・選択(30,40): margin 10% = 3秒 → 23<=30 && 40<=47 を満たす → 維持
        let window = CropWindow(start: 20, end: 50)
        let range = TrimRange(start: 30, end: 40, duration: 600, maxRange: 600)
        let synced = WaveformCropMath.syncedWindow(window, to: range, duration: 600)
        #expect(synced == window)
    }

    @Test
    func syncedWindow_recentersWhenSelectionOutside() {
        // 窓(20,50) から選択がはみ出た → 選択中心で再配置
        let window = CropWindow(start: 20, end: 50)
        let range = TrimRange(start: 45, end: 55, duration: 600, maxRange: 600)
        let synced = WaveformCropMath.syncedWindow(window, to: range, duration: 600)
        #expect(synced == WaveformCropMath.zoomWindow(range: range, duration: 600))
    }

    @Test
    func syncedWindow_zeroWindow_fallsBackToZoomWindow() {
        let window = CropWindow(start: 0, end: 0)
        let range = TrimRange(start: 30, end: 40, duration: 600, maxRange: 600)
        let synced = WaveformCropMath.syncedWindow(window, to: range, duration: 600)
        #expect(synced == WaveformCropMath.zoomWindow(range: range, duration: 600))
    }

    @Test
    func syncedWindow_isStable() {
        // zoomWindow の結果は選択端が中央から1/3の位置 → margin(10%)より内側。
        // よって再度同期しても窓は動かない（発振しない）
        let range = TrimRange(start: 595, end: 600, duration: 600, maxRange: 600)
        let first = WaveformCropMath.zoomWindow(range: range, duration: 600)
        let second = WaveformCropMath.syncedWindow(first, to: range, duration: 600)
        #expect(second == first)
    }

    // MARK: - ズーム窓の移動

    @Test
    func pannedWindow_movesProportionally() {
        // 幅300pt に窓30秒: 150pt ドラッグ = 窓幅の半分 = 15秒
        let window = CropWindow(start: 100, end: 130)
        let panned = WaveformCropMath.pannedWindow(window, translationX: 150, width: 300, duration: 600)
        #expect(approx(panned.start, 85))
        #expect(approx(panned.end, 115))
    }

    @Test
    func pannedWindow_clampsAtZero() {
        let window = CropWindow(start: 5, end: 35)
        let panned = WaveformCropMath.pannedWindow(window, translationX: 200, width: 300, duration: 600)
        #expect(approx(panned.start, 0))
        #expect(approx(panned.end, 30))
    }

    @Test
    func pannedWindow_clampsAtDuration() {
        let window = CropWindow(start: 580, end: 600)
        let panned = WaveformCropMath.pannedWindow(window, translationX: -200, width: 300, duration: 600)
        #expect(approx(panned.end, 600))
        #expect(approx(panned.start, 580))
    }

    // MARK: - リサンプル（下段描画用）

    @Test
    func resample_emptySamples_returnsEmpty() {
        let result = WaveformCropMath.resample([], in: CropWindow(start: 0, end: 10), sampleDuration: 10, count: 100)
        #expect(result.isEmpty)
    }

    @Test
    func resample_uniformSamples() {
        let samples = [Float](repeating: 1.0, count: 1000)
        let result = WaveformCropMath.resample(samples, in: CropWindow(start: 0, end: 10), sampleDuration: 10, count: 50)
        #expect(result.count == 50)
        #expect(result.allSatisfy { abs($0 - 1.0) < 0.0001 })
    }

    @Test
    func resample_peakHoldPreservesTransients() {
        // 500サンプル中1つだけ 1.0、他は 0.1 → ピークホールドで 1.0 が残る
        var samples = [Float](repeating: 0.1, count: 500)
        samples[250] = 1.0
        let result = WaveformCropMath.resample(samples, in: CropWindow(start: 0, end: 10), sampleDuration: 10, count: 1)
        #expect(result.count == 1)
        #expect(abs(result[0] - 1.0) < 0.0001)
    }

    @Test
    func resample_respectsWindow() {
        // 前半0.0・後半1.0 のサンプル: 窓を後半にすると全て1.0
        var samples = [Float](repeating: 0.0, count: 100)
        for i in 50..<100 { samples[i] = 1.0 }
        let secondHalf = WaveformCropMath.resample(samples, in: CropWindow(start: 5, end: 10), sampleDuration: 10, count: 10)
        #expect(secondHalf.allSatisfy { abs($0 - 1.0) < 0.0001 })

        let firstHalf = WaveformCropMath.resample(samples, in: CropWindow(start: 0, end: 5), sampleDuration: 10, count: 10)
        #expect(firstHalf.allSatisfy { abs($0 - 0.0) < 0.0001 })
    }

    @Test
    func resample_returnsRequestedCount() {
        let samples = [Float](repeating: 0.5, count: 8000)
        for count in [16, 64, 200] {
            let result = WaveformCropMath.resample(samples, in: CropWindow(start: 100, end: 130), sampleDuration: 600, count: count)
            #expect(result.count == count)
        }
    }

    @Test
    func resample_zeroWidthWindow_returnsEmpty() {
        let samples = [Float](repeating: 0.5, count: 100)
        let result = WaveformCropMath.resample(samples, in: CropWindow(start: 5, end: 5), sampleDuration: 10, count: 10)
        #expect(result.isEmpty)
    }

    // MARK: - CropWindow

    @Test
    func cropWindow_normalizesOrder() {
        let window = CropWindow(start: 30, end: 10)
        #expect(approx(window.start, 10))
        #expect(approx(window.end, 30))
        #expect(approx(window.width, 20))
    }

    @Test
    func cropWindow_contains() {
        let window = CropWindow(start: 10, end: 20)
        #expect(window.contains(10))
        #expect(window.contains(15))
        #expect(window.contains(20))
        #expect(!window.contains(9.9))
        #expect(!window.contains(20.1))
    }
}