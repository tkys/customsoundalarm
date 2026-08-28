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

    // MARK: - 下段の描画バケット数（#82-1: バケット数＝バー本数）

    /// 下段は自前 Canvas が 1バー=4pt ピッチ（幅2+間隔2）で描くため、バケット数は
    /// バー本数と一致させる。1バケット＝1バーで描くことで、resample が取ったピークから
    /// さらにピークを取る二重集約（振幅飽和・#82-1）を防ぐ。
    /// ※ #79 当時の「バケット数＝バー幅（1サンプル=1pt）」は WaveformShape 前提の
    ///   古い契約。自前 Canvas 化（#81-1）以降はこちらが正しい契約。
    @Test
    func zoomBucketCount_equalsBarCount() {
        // 390pt / 4ptピッチ → 97本
        #expect(WaveformCropMath.zoomBucketCount(viewWidth: 390) == 97)
        #expect(WaveformCropMath.zoomBucketCount(viewWidth: 120) == 30)
        #expect(WaveformCropMath.zoomBucketCount(viewWidth: 4) == 1)
    }

    @Test
    func zoomBucketCount_customPitch() {
        #expect(WaveformCropMath.zoomBucketCount(viewWidth: 100, barPitch: 5) == 20)
        #expect(WaveformCropMath.zoomBucketCount(viewWidth: 100, barPitch: 10) == 10)
    }

    @Test
    func zoomBucketCount_minimumIsOne() {
        #expect(WaveformCropMath.zoomBucketCount(viewWidth: 0) == 1)
        #expect(WaveformCropMath.zoomBucketCount(viewWidth: -10) == 1)
        #expect(WaveformCropMath.zoomBucketCount(viewWidth: 0.4) == 1)
        #expect(WaveformCropMath.zoomBucketCount(viewWidth: 100, barPitch: 0) == 1)
        #expect(WaveformCropMath.zoomBucketCount(viewWidth: 100, barPitch: -4) == 1)
    }

    /// バケット数＝バー本数の契約: 全バーがバー幅内に収まる（描画時に切り捨てられない）
    @Test
    func zoomBucketCount_allBarsFitInWidth() {
        for width in [390.0, 200.0, 97.0, 12.0] {
            let count = WaveformCropMath.zoomBucketCount(viewWidth: width)
            #expect(Double(count) * 4 <= width)
            #expect(Double(count + 1) * 4 > width)
        }
    }

    /// 振幅が飽和しないこと（#82-1 回帰防止）: 一定の入力に対し出力が
    /// 最大値（1.0）に張り付かない。0.5 の入力は 0.5 のまま出力される
    @Test
    func resample_constantHalfAmplitude_doesNotSaturate() {
        let samples = [Float](repeating: 0.5, count: 8000)
        let barCount = WaveformCropMath.zoomBucketCount(viewWidth: 390)
        let result = WaveformCropMath.resample(
            samples,
            in: CropWindow(start: 0, end: 60),
            sampleDuration: 600,
            count: barCount
        )
        #expect(result.count == barCount)
        #expect(result.allSatisfy { abs($0 - 0.5) < 0.0001 })
        #expect((result.max() ?? 1.0) < 1.0)
    }

    /// 静かな区間の窓では静かなまま出る（静音区間のピークが無視されない）
    @Test
    func resample_quietWindow_staysQuiet() {
        var samples = [Float](repeating: 0.1, count: 6000)
        for i in 3000..<6000 { samples[i] = 1.0 }
        // 窓は前半（静かな区間）のみ
        let result = WaveformCropMath.resample(
            samples,
            in: CropWindow(start: 0, end: 30),
            sampleDuration: 60,
            count: WaveformCropMath.zoomBucketCount(viewWidth: 390)
        )
        #expect((result.max() ?? 1.0) < 0.2)
    }

    /// バグ1の再発防止: 選択範囲（＝窓）に対応するサンプルが正しい時間範囲から
    /// 取れていること。サンプル値に時刻をエンコードし、出力バケットの値が
    /// 窓内の正しい時刻を指すことを検証する（#79 の本質的契約は維持）
    @Test
    func resample_takesSamplesFromCorrectTimeRange_regression79() {
        // 100秒の音源を1000サンプルで表す。samples[i] = i/1000（= 時刻/100 に等しい）
        let sampleDuration = 100.0
        let total = 1000
        let samples = (0..<total).map { Float($0) / Float(total) * Float(sampleDuration) / 100.0 }
        // → samples[i] ≈ 時刻(i/10) / 100。値自体が「時刻/100」をエンコードする

        let window = CropWindow(start: 50, end: 60) // 50〜60秒のみ取り出す
        let count = 100
        let result = WaveformCropMath.resample(samples, in: window, sampleDuration: sampleDuration, count: count)

        #expect(result.count == count)
        // 各バケットのピーク（= バケット末尾の時刻）は窓内の時刻をエンコードしている。
        // バケット j のカバー時刻は [50 + j*0.1, 50 + (j+1)*0.1)
        for j in 0..<count {
            let expectedTime = 50.0 + Double(j + 1) / Double(count) * 10.0
            #expect(abs(Double(result[j]) * 100.0 - expectedTime) < 0.11) // バケット幅(0.1秒)の誤差内
        }
        // 先頭バケットは 50〜50.1秒の範囲から（窓の外の 0〜50秒を拾っていない）
        #expect(Double(result[0]) * 100.0 >= 50.0)
        #expect(Double(result[0]) * 100.0 <= 50.1 + 0.0001)
    }

    /// resample の出力が窓の時間方向に単調増加になること（インデックス逆転していないこと）
    @Test
    func resample_isMonotonicWithTimeEncodedSamples() {
        let sampleDuration = 50.0
        let samples = (0..<5000).map { Float($0) }
        let window = CropWindow(start: 10, end: 40)
        let result = WaveformCropMath.resample(samples, in: window, sampleDuration: sampleDuration, count: 50)
        #expect(result.count == 50)
        for j in 1..<result.count {
            #expect(result[j] > result[j - 1])
        }
    }

    // MARK: - 再生中の窓追従（#79 バグ2）

    @Test
    func followPlayback_insideWindow_keepsWindow() {
        let window = CropWindow(start: 100, end: 130)
        let followed = WaveformCropMath.windowFollowingPlayback(current: window, playhead: 115, duration: 600)
        #expect(followed == window)
    }

    @Test
    func followPlayback_outsideWindow_recentersAtLeadFraction() {
        // ヘッドが窓の終端を超えた → ヘッドが窓の25%位置に来るよう再配置
        let window = CropWindow(start: 100, end: 130)
        let followed = WaveformCropMath.windowFollowingPlayback(current: window, playhead: 135, duration: 600)
        #expect(approx(followed.start, 135 - 30 * 0.25))
        #expect(approx(followed.start, 127.5))
        #expect(approx(followed.width, 30))
        #expect(followed.contains(135))
    }

    @Test
    func followPlayback_clampsAtEnd() {
        let window = CropWindow(start: 580, end: 600)
        // ヘッドが末尾を超えた → 末尾にクランプ（start = 600 - 窓幅20）
        let followed = WaveformCropMath.windowFollowingPlayback(current: window, playhead: 601, duration: 600)
        #expect(approx(followed.start, 580))
        #expect(approx(followed.end, 600))
    }

    @Test
    func followPlayback_zeroWidth_returnsCurrent() {
        let window = CropWindow(start: 0, end: 0)
        let followed = WaveformCropMath.windowFollowingPlayback(current: window, playhead: 10, duration: 600)
        #expect(followed == window)
    }

    // MARK: - 時間フォーマット（#79-6）

    @Test
    func formatTime_basics() {
        #expect(WaveformCropMath.formatTime(0) == "0:00")
        #expect(WaveformCropMath.formatTime(5) == "0:05")
        #expect(WaveformCropMath.formatTime(65) == "1:05")
        #expect(WaveformCropMath.formatTime(3599) == "59:59")
        #expect(WaveformCropMath.formatTime(3600) == "60:00")
        #expect(WaveformCropMath.formatTime(3661) == "61:01")
    }

    @Test
    func formatTime_negativeClampsToZero() {
        #expect(WaveformCropMath.formatTime(-3) == "0:00")
    }

    @Test
    func formatTime_truncatesFraction() {
        #expect(WaveformCropMath.formatTime(59.9) == "0:59")
        #expect(WaveformCropMath.formatTime(60.5) == "1:00")
    }

    // MARK: - 高精度時間フォーマット（#80-3）

    @Test
    func formatPreciseTime_basics() {
        #expect(WaveformCropMath.formatPreciseTime(0) == "00:00.00")
        #expect(WaveformCropMath.formatPreciseTime(5.7) == "00:05.70")
        #expect(WaveformCropMath.formatPreciseTime(65.5) == "01:05.50")
        #expect(WaveformCropMath.formatPreciseTime(3661.23) == "61:01.23")
    }

    @Test
    func formatPreciseTime_negativeClampsToZero() {
        #expect(WaveformCropMath.formatPreciseTime(-0.5) == "00:00.00")
    }

    @Test
    func formatPreciseTime_roundsToHundredth() {
        // 5.706秒 → 570.6 → 571（1/100秒に四捨五入）
        #expect(WaveformCropMath.formatPreciseTime(5.706) == "00:05.71")
        // 5.704秒 → 570.4 → 570
        #expect(WaveformCropMath.formatPreciseTime(5.704) == "00:05.70")
    }

    // MARK: - 時間目盛り（#80-5）

    @Test
    func rulerStep_picksNiceStep() {
        // 30秒 → 5秒刻み（6ラベル）
        #expect(WaveformCropMath.rulerStep(forSpan: 30) == 5)
        // 600秒 → 120秒刻み（6ラベル）
        #expect(WaveformCropMath.rulerStep(forSpan: 600) == 120)
        // 8秒 → 2秒刻み（5ラベル）
        #expect(WaveformCropMath.rulerStep(forSpan: 8) == 2)
        // 100秒 → 15秒では6.67ラベルで超過 → 30秒刻み
        #expect(WaveformCropMath.rulerStep(forSpan: 100) == 30)
        // 60秒 → 10秒刻み（6ラベル）
        #expect(WaveformCropMath.rulerStep(forSpan: 60) == 10)
    }

    @Test
    func rulerStep_respectsTargetCount() {
        // targetCount を大きくすれば細かい刻みが選ばれる
        #expect(WaveformCropMath.rulerStep(forSpan: 100, targetCount: 10) == 10)
        #expect(WaveformCropMath.rulerStep(forSpan: 30, targetCount: 3) == 10)
    }

    @Test
    func rulerStep_invalidInput_returnsLargestCandidate() {
        #expect(WaveformCropMath.rulerStep(forSpan: 0) == 3600)
        #expect(WaveformCropMath.rulerStep(forSpan: -5) == 3600)
    }

    @Test
    func rulerTimes_evenSteps() {
        let times = WaveformCropMath.rulerTimes(span: 30, step: 5)
        #expect(times == [0, 5, 10, 15, 20, 25, 30])
    }

    @Test
    func rulerTimes_includesClippedEnd() {
        // 割り切れない場合も span 以下の刻みまで列挙
        let times = WaveformCropMath.rulerTimes(span: 30, step: 20)
        #expect(times == [0, 20])
    }

    @Test
    func rulerTimes_invalidInput_returnsEmpty() {
        #expect(WaveformCropMath.rulerTimes(span: 0, step: 5).isEmpty)
        #expect(WaveformCropMath.rulerTimes(span: 30, step: 0).isEmpty)
    }

    // MARK: - 目盛りラベルのクランプと間引き（#81-3）

    @Test
    func clampedRulerX_leftEdgeClampsToZero() {
        #expect(WaveformCropMath.clampedRulerX(x: -5, barWidth: 390, labelWidth: 34) == 0)
        #expect(WaveformCropMath.clampedRulerX(x: 0, barWidth: 390, labelWidth: 34) == 0)
    }

    @Test
    func clampedRulerX_rightEdgeClampsInside() {
        // 右端: x = barWidth - labelWidth に収める（右端のラベルが切れない）
        #expect(abs(WaveformCropMath.clampedRulerX(x: 390, barWidth: 390, labelWidth: 34) - 356) < 0.0001)
        #expect(abs(WaveformCropMath.clampedRulerX(x: 400, barWidth: 390, labelWidth: 34) - 356) < 0.0001)
    }

    @Test
    func clampedRulerX_middleUnchanged() {
        #expect(abs(WaveformCropMath.clampedRulerX(x: 150, barWidth: 390, labelWidth: 34) - 150) < 0.0001)
    }

    @Test
    func clampedRulerX_invalidInput_returnsX() {
        #expect(WaveformCropMath.clampedRulerX(x: 150, barWidth: 0, labelWidth: 34) == 150)
        #expect(WaveformCropMath.clampedRulerX(x: -5, barWidth: 390, labelWidth: 0) == -5)
    }

    @Test
    func rulerStepWithLabelWidth_noOverlap() {
        // 十分な幅なら従来どおり: 30秒/390pt/ラベル34pt → 5秒刻み（間隔65pt ≥ 34+8）
        #expect(WaveformCropMath.rulerStep(forSpan: 30, barWidth: 390, labelWidth: 34) == 5)
    }

    @Test
    func rulerStepWithLabelWidth_thinsOutWhenTight() {
        // 60秒/200pt では 10秒刻み（間隔33.3pt）がラベル幅に満たない → 15秒刻みに間引き
        #expect(WaveformCropMath.rulerStep(forSpan: 60, barWidth: 200, labelWidth: 34) == 15)
    }

    @Test
    func rulerStepWithLabelWidth_fallsBackToLargest() {
        // 2時間/100pt: どの候補も間隔条件を満たさず、最大候補で1〜2ラベルに
        #expect(WaveformCropMath.rulerStep(forSpan: 7200, barWidth: 100, labelWidth: 34) == 3600)
    }

    @Test
    func rulerStepWithLabelWidth_invalidInput() {
        #expect(WaveformCropMath.rulerStep(forSpan: 0, barWidth: 390, labelWidth: 34) == 3600)
        #expect(WaveformCropMath.rulerStep(forSpan: 30, barWidth: -1, labelWidth: 34) == 3600)
    }
}