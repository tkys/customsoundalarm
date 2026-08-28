import Foundation
import CoreGraphics

/// 波形クロップUI（#77）のズーム窓。
/// 上段（全体波形）の選択範囲周辺の時間窓を表す。
struct CropWindow: Equatable, Sendable {
    var start: Double
    var end: Double

    init(start: Double, end: Double) {
        self.start = min(start, end)
        self.end = max(start, end)
    }

    var width: Double { end - start }

    func contains(_ time: Double) -> Bool {
        time >= start && time <= end
    }
}

/// 波形クロップUI（#77）の座標→時間変換・ズーム窓の算出・同期の純粋関数群。
///
/// 設計意図:
/// - 範囲のクランプは常に `TrimRange`（既存の純粋ロジック）が担う
/// - この型は「座標系の変換」と「上段/下段の窓同期」のみを担い、View に散らさない
/// - #76 対策: 上段（全体）は 1pt≈1.7秒（600秒ファイル）になるため、
///   下段（拡大）で選択周辺のみを表示して秒以下の調整を可能にする
enum WaveformCropMath {

    // MARK: - 上段（全体波形）の座標変換

    /// 上段の x 座標 → 時間。`[0, width]` を `[0, duration]` に写像しクランプする
    static func overviewTime(atX x: Double, width: Double, duration: Double) -> Double {
        guard width > 0, duration > 0 else { return 0 }
        let fraction = min(max(x / width, 0), 1)
        return fraction * duration
    }

    /// 時間 → 上段の x 座標
    static func overviewX(for time: Double, width: Double, duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        let fraction = min(max(time / duration, 0), 1)
        return fraction * width
    }

    // MARK: - 下段（拡大波形）の座標変換

    /// 下段の描画バケット数。
    ///
    /// DSWaveformImage の `LinearWaveformRenderer` はサンプルを**1サンプル=1pt で描き、
    /// 引き伸ばさない**（余白があれば右寄せになる）。
    /// したがってバケット数はバーの幅（pt）と一致させなければならない
    /// （#79 バグ1: 幅の1/3のバケット数だったため波形が右1/3にだけ描画されていた）。
    /// 併せて `Waveform.Configuration(scale: 1)` で実画面スケールを無効化して使うこと。
    static func zoomBucketCount(viewWidth: Double) -> Int {
        max(Int(viewWidth), 1)
    }

    /// 下段の x 座標 → 時間。`[0, width]` を `window` に写像する
    static func zoomTime(atX x: Double, width: Double, window: CropWindow) -> Double {
        guard width > 0, window.width > 0 else { return window.start }
        let fraction = min(max(x / width, 0), 1)
        return window.start + fraction * window.width
    }

    /// 時間 → 下段の x 座標。窓の外の時間はクランプされる
    static func zoomX(for time: Double, width: Double, window: CropWindow) -> Double {
        guard window.width > 0 else { return 0 }
        let clamped = min(max(time, window.start), window.end)
        return (clamped - window.start) / window.width * width
    }

    // MARK: - ズーム窓の算出

    /// 選択範囲からズーム窓を算出する。
    ///
    /// 方針: 選択範囲を中心に置き、選択幅の3倍（最低8秒・最大60秒）の窓を取る。
    /// - 最低8秒: 窓が狭すぎると前後の文脈が見えず、調整の基準が失われる
    /// - 最大60秒: 窓が広すぎると拡大効果が消え #76 の精度問題が再発する
    /// - `[0, duration]` に収まるよう端では寄せる
    static func zoomWindow(range: TrimRange, duration: Double) -> CropWindow {
        guard duration > 0 else { return CropWindow(start: 0, end: 0) }
        let selectionWidth = min(range.width, duration)
        let desired = min(max(selectionWidth * 3, 8), 60)
        let center = (range.start + range.end) / 2

        var start = center - desired / 2
        var end = center + desired / 2
        if start < 0 {
            start = 0
            end = min(desired, duration)
        }
        if end > duration {
            end = duration
            start = max(0, duration - desired)
        }
        return CropWindow(start: start, end: end)
    }

    /// ズーム窓の追従判定。
    /// 選択範囲が窓の内側（両端に marginFraction 分の余白）にあれば現状維持、
    /// はみ出したら選択範囲を中心に再配置する。
    /// `zoomWindow` が返す窓は選択端が中央から1/3の位置にあるため、
    /// marginFraction < 1/3 なら追従の安定性（発振しないこと）が保証される。
    static func syncedWindow(
        _ window: CropWindow,
        to range: TrimRange,
        duration: Double,
        marginFraction: Double = 0.1
    ) -> CropWindow {
        guard window.width > 0 else {
            return zoomWindow(range: range, duration: duration)
        }
        let margin = window.width * marginFraction
        if range.start >= window.start + margin && range.end <= window.end - margin {
            return window
        }
        return zoomWindow(range: range, duration: duration)
    }

    /// ズーム窓の平行移動（下段の波形ドラッグ）。
    /// 移動量は「下段の表示幅に対する割合」で受け取り、窓の時間スケールに変換する。
    /// `[0, duration]` にクランプする。
    static func pannedWindow(
        _ window: CropWindow,
        translationX dx: Double,
        width: Double,
        duration: Double
    ) -> CropWindow {
        guard window.width > 0, width > 0 else { return window }
        let delta = dx / width * window.width
        var start = window.start - delta
        var end = window.end - delta
        if start < 0 {
            start = 0
            end = window.width
        }
        if end > duration {
            end = duration
            start = max(0, duration - window.width)
        }
        return CropWindow(start: start, end: end)
    }

    /// 再生中のズーム窓追従（#79 バグ2）。
    /// 再生ヘッドが窓の外に出たら、ヘッドが窓の先頭から `leadFraction`（既定0.25）の
    /// 位置に来るよう窓を再配置する。窓内なら現状維持（再生中の不用意なスクロールを防ぐ）。
    static func windowFollowingPlayback(
        current: CropWindow,
        playhead: Double,
        duration: Double,
        leadFraction: Double = 0.25
    ) -> CropWindow {
        guard current.width > 0, duration > 0 else { return current }
        if current.contains(playhead) { return current }
        var start = playhead - current.width * leadFraction
        if start < 0 { start = 0 }
        if start + current.width > duration {
            start = max(0, duration - current.width)
        }
        return CropWindow(start: start, end: min(start + current.width, duration))
    }

    // MARK: - 時間表示フォーマット

    /// 秒 → "m:ss" 形式。負数は 0 扱い。1時間超は m が60を超える（"60:00" 等）
    static func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    /// 秒 → "00:05.70" 形式（1/100秒まで・#80-3）。
    /// 再生位置の主役表示に使う。負数は 0 扱い。
    static func formatPreciseTime(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let totalHundredths = Int((clamped * 100).rounded())
        let m = totalHundredths / 6000
        let s = (totalHundredths % 6000) / 100
        let cs = totalHundredths % 100
        return String(format: "%02d:%02d.%02d", m, s, cs)
    }

    // MARK: - 時間目盛り（#80-5）

    /// 目盛りに使う刻み幅の候補（秒）
    private static let rulerStepCandidates: [Double] = [
        1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600
    ]

    /// 表示幅（秒）から目盛りの刻み幅を選ぶ。
    /// ラベル数が `targetCount`（既定6）を超えない最小の「きりの良い」刻みを選ぶ。
    /// どの候補でも収まらないときは最大候補（3600）を返す。
    static func rulerStep(forSpan span: Double, targetCount: Int = 6) -> Double {
        guard span > 0, targetCount > 0 else { return rulerStepCandidates.last! }
        for step in rulerStepCandidates where span / step <= Double(targetCount) {
            return step
        }
        return rulerStepCandidates.last!
    }

    /// ラベルの実描画幅を考慮した刻み幅の選択（#81-3）。
    ///
    /// 隣接ラベルの間隔（px）が `labelWidth + minGap` に満たない刻みは除外することで、
    /// ラベル同士の重なりを防ぐ。ラベル数の上限（targetCount）との両方を満たす
    /// 最小の候補を返し、無い場合は最大候補（3600）を返す。
    ///
    /// - Parameters:
    ///   - span: 表示幅（秒）
    ///   - barWidth: 目盛りを描くバーの幅（pt）
    ///   - labelWidth: ラベル1つの実描画幅（pt）
    ///   - minGap: ラベル間の最小間隔（pt）
    ///   - targetCount: ラベル数の上限
    static func rulerStep(
        forSpan span: Double,
        barWidth: Double,
        labelWidth: Double,
        minGap: Double = 8,
        targetCount: Int = 6
    ) -> Double {
        guard span > 0, barWidth > 0, labelWidth >= 0, minGap >= 0 else {
            return rulerStepCandidates.last!
        }
        let pxPerSecond = barWidth / span
        for step in rulerStepCandidates {
            let labelSpacing = step * pxPerSecond
            if span / step <= Double(targetCount) && labelSpacing >= labelWidth + minGap {
                return step
            }
        }
        return rulerStepCandidates.last!
    }

    /// 目盛りラベルのX位置を両端で内側にクランプする（#81-3）。
    /// 最初のラベルは左端で切れず（x >= 0）、最後のラベルは右端に収まる（x <= barWidth - labelWidth）。
    static func clampedRulerX(x: Double, barWidth: Double, labelWidth: Double) -> Double {
        guard barWidth > 0, labelWidth > 0 else { return x }
        return min(max(x, 0), max(0, barWidth - labelWidth))
    }

    /// 目盛りの時刻一覧（0 から step 刻み、span 以下）
    static func rulerTimes(span: Double, step: Double) -> [Double] {
        guard span > 0, step > 0 else { return [] }
        var times: [Double] = []
        var t = 0.0
        while t <= span + 0.0001 {
            times.append(t)
            t += step
        }
        return times
    }

    // MARK: - サンプルのリサンプル（下段描画用）

    /// 全体サンプル配列から窓の範囲のみをピークホールドでリサンプルする。
    ///
    /// - Parameters:
    ///   - samples: 全体波形の振幅配列（0...1）
    ///   - window: 取り出す時間窓
    ///   - sampleDuration: `samples` がカバーする全体の秒数
    ///   - count: 出力バケット数（下段の描画幅に対応）
    /// - Returns: 窓の範囲の振幅配列。入力が空の場合は空配列
    ///
    /// ピークホールド（平均でなく最大値）なのは、
    /// 短いトランジェント（ドラムのアタック等）が平均で潰れないようにするため。
    static func resample(
        _ samples: [Float],
        in window: CropWindow,
        sampleDuration: Double,
        count: Int
    ) -> [Float] {
        guard !samples.isEmpty, sampleDuration > 0, count > 0, window.width > 0 else { return [] }
        let samplesPerSecond = Double(samples.count) / sampleDuration
        var result = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let t0 = window.start + Double(i) / Double(count) * window.width
            let t1 = window.start + Double(i + 1) / Double(count) * window.width
            let index0 = max(0, min(Int(t0 * samplesPerSecond), samples.count))
            let index1 = max(0, min(Int(ceil(t1 * samplesPerSecond)), samples.count))
            guard index1 > index0 else { continue }
            var peak: Float = 0
            for j in index0..<index1 where samples[j] > peak {
                peak = samples[j]
            }
            result[i] = peak
        }
        return result
    }
}