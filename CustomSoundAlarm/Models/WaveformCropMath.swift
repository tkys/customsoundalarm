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