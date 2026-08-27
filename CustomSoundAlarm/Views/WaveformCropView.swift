import SwiftUI
import DSWaveformImage
import DSWaveformImageViews

/// 波形ベースのクロップUI（#77）。二段構え:
/// - **上段（全体波形）**: ファイル全長の俯瞰と大まかな位置決め（DSWaveformImage で描画）
/// - **下段（拡大波形）**: 選択範囲周辺の拡大表示で秒以下の調整（#76 の精度問題を解決）
///
/// 設計メモ:
/// - 範囲のクランプは常に `TrimRange`（既存の純粋ロジック）が担う
/// - 座標→時間の変換と窓同期は `WaveformCropMath`（純粋関数）が担う
/// - 波形サンプル取得は非同期。生成中はプレースホルダを出し UI をブロックしない
/// - #36 の修正を踏襲: ハンドルは `.frame` / `.contentShape` を `.offset` の**前**に置く。
///   pan は panBaseRange / panBaseWindow（ドラッグ開始時の固定値）を基準に適用する
struct WaveformCropView: View {
    @Binding var startTime: Double
    @Binding var endTime: Double

    /// 波形描画元の音声URL（動画の場合は抽出済みの一時m4a）
    let audioURL: URL
    let duration: Double
    /// 切り出し上限（秒）。音声ファイルは無上限（= duration を渡す）
    var maxRange: Double = 600

    /// スクラブ再生（任意）。nil ならタップ再生は無効
    var previewer: TrimPreviewer?
    /// スクラブ再生対象のURL（音声抽出前などで nil の場合もある）
    var playURL: URL?

    /// 下段描画用の全体サンプル（非同期ロード・UI非ブロック）
    @State private var samples: [Float]?
    @State private var zoomWindow = CropWindow(start: 0, end: 0)

    /// ドラッグ中のハンドル識別（当たり判定の排他と Haptic 用）
    @State private var draggingHandle: Handle?

    /// 上段 pan の基準範囲（#36: 現在値基準だと二次関数的に加速するため固定値を使う）
    @State private var panBaseRange: TrimRange?
    /// 下段 pan（窓移動）の基準（同上）
    @State private var panBaseWindow: CropWindow?

    @State private var overviewWidth: CGFloat = 0
    @State private var zoomWidth: CGFloat = 0

    private let overviewHeight: CGFloat = 56
    private let zoomHeight: CGFloat = 72
    private let handleWidth: CGFloat = 6
    private let overviewSpace = "waveOverviewSpace"
    private let zoomSpace = "waveZoomSpace"
    /// 下段のサンプル解像度（600秒ファイルで窓8秒時に約100バケット）
    private let sampleCount = 8000

    enum Handle: Hashable {
        case startOverview, endOverview, panOverview
        case startZoom, endZoom, panZoom
    }

    var body: some View {
        let range = currentRange
        VStack(spacing: 8) {
            overviewBar(range: range)
            timeLabels(range: range)
            zoomBar(range: range)
        }
        .task(id: audioURL) {
            await loadSamples()
        }
        .onAppear {
            if zoomWindow.width <= 0 {
                zoomWindow = WaveformCropMath.zoomWindow(range: range, duration: duration)
            }
        }
        .onChange(of: startTime) { _, _ in
            syncZoomWindow()
        }
        .onChange(of: endTime) { _, _ in
            syncZoomWindow()
        }
    }

    // MARK: - Range / Window

    private var currentRange: TrimRange {
        TrimRange(
            start: startTime,
            end: endTime,
            duration: duration,
            maxRange: maxRange
        )
    }

    /// 選択範囲の変化にズーム窓を追従させる（はみ出したら再中心化）
    private func syncZoomWindow() {
        zoomWindow = WaveformCropMath.syncedWindow(
            zoomWindow,
            to: currentRange,
            duration: duration
        )
    }

    private func loadSamples() async {
        samples = nil
        // 波形サンプルの生成は重い（600秒≈2600万サンプル）ため非同期で。
        // 失敗してもクロップ自体は可能（ディムとハンドルのみの表示になる）
        let analyzer = WaveformAnalyzer()
        if let result = try? await analyzer.samples(fromAudioAt: audioURL, count: sampleCount, qos: .userInitiated) {
            if !Task.isCancelled {
                samples = result
            }
        }
        if !Task.isCancelled {
            zoomWindow = WaveformCropMath.zoomWindow(range: currentRange, duration: duration)
        }
    }

    // MARK: - 上段（全体波形）

    private func overviewBar(range: TrimRange) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let leading = WaveformCropMath.overviewX(for: range.start, width: width, duration: duration)
            let trailing = width - WaveformCropMath.overviewX(for: range.end, width: width, duration: duration)
            let selectedWidth = width - leading - trailing

            ZStack(alignment: .leading) {
                // 1. 全体波形（DSWaveformImage・生成中はプレースホルダ）
                WaveformView(audioURL: audioURL) { shape in
                    shape.fill(Color.accentColor.opacity(0.85))
                } placeholder: {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                .frame(width: width, height: overviewHeight)

                // 2. 選択範囲外のディム
                HStack(spacing: 0) {
                    Color.black.opacity(0.55).frame(width: max(leading, 0))
                    Color.clear.frame(width: max(selectedWidth, 0))
                    Color.black.opacity(0.55).frame(width: max(trailing, 0))
                }
                .frame(height: overviewHeight)
                .allowsHitTesting(false)

                // 3. 選択範囲の枠線
                Rectangle()
                    .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5)
                    .frame(width: max(selectedWidth, 0), height: overviewHeight)
                    .offset(x: leading)
                    .allowsHitTesting(false)

                // 4. 選択範囲内タップでスクラブ / ドラッグで範囲移動
                overviewScrubArea(width: max(selectedWidth, 0), offset: leading, range: range)

                // 5. 左右ハンドル
                overviewHandle(kind: .startOverview, x: leading)
                overviewHandle(kind: .endOverview, x: leading + selectedWidth)

                // 6. 再生ヘッド
                if previewer?.isPlaying == true, let previewer {
                    let x = WaveformCropMath.overviewX(for: previewer.currentTime, width: width, duration: duration)
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: 2.5, height: overviewHeight - 4)
                        .offset(x: x)
                        .shadow(color: .red.opacity(0.4), radius: 3)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: overviewSpace)
            .background(
                Color.clear
                    .onAppear { overviewWidth = width }
                    .onChange(of: width) { _, newWidth in overviewWidth = newWidth }
            )
        }
        .frame(height: overviewHeight)
    }

    /// 上段の選択範囲内操作（VideoTrimmerBar と同一パターン）:
    /// - 短いタップ → スクラブ（再生位置指定）
    /// - ドラッグ → 選択範囲全体の平行移動（panBaseRange 基準・#36）
    private func overviewScrubArea(width: CGFloat, offset: CGFloat, range: TrimRange) -> some View {
        let tapThreshold: CGFloat = 8

        return Color.clear
            .frame(width: width, height: overviewHeight)
            .offset(x: offset)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(overviewSpace))
                    .onChanged { value in
                        guard abs(value.translation.width) >= tapThreshold else { return }
                        if draggingHandle != .panOverview {
                            draggingHandle = .panOverview
                            // 基準はドラッグ開始時に1度だけ固定する（#36 累積バグ対策）
                            panBaseRange = currentRange
                            previewer?.stop()
                        }
                        let delta = value.translation.width / max(overviewWidth, 1) * duration
                        let base = panBaseRange ?? currentRange
                        let clamped = base.movingRange(by: delta)
                        startTime = clamped.start
                        endTime = clamped.end
                    }
                    .onEnded { value in
                        if draggingHandle == .panOverview {
                            draggingHandle = nil
                            panBaseRange = nil
                        } else if let playURL, let previewer {
                            // タップ → スクラブ
                            let time = WaveformCropMath.overviewTime(atX: value.location.x, width: max(overviewWidth, 1), duration: duration)
                            let scrubTime = min(max(time, range.start), range.end)
                            previewer.play(url: playURL, from: scrubTime, to: range.end)
                        }
                    }
            )
    }

    /// 上段ハンドル。⚠️ `.frame` / `.contentShape` を `.offset` の前に（#36 原因1）
    private func overviewHandle(kind: Handle, x: CGFloat) -> some View {
        handleShape(isActive: draggingHandle == kind)
            .frame(width: handleWidth * 3, height: overviewHeight)
            .contentShape(Rectangle())
            .offset(x: x - handleWidth * 3 / 2)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(overviewSpace))
                    .onChanged { value in
                        if draggingHandle != kind {
                            draggingHandle = kind
                            previewer?.stop()
                        }
                        let target = WaveformCropMath.overviewTime(
                            atX: max(0, value.location.x),
                            width: max(overviewWidth, 1),
                            duration: duration
                        )
                        switch kind {
                        case .startOverview:
                            startTime = currentRange.movingStart(to: target).start
                        case .endOverview:
                            endTime = currentRange.movingEnd(to: target).end
                        default:
                            break
                        }
                    }
                    .onEnded { _ in draggingHandle = nil }
            )
    }

    // MARK: - 下段（拡大波形）

    private func zoomBar(range: TrimRange) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let leading = WaveformCropMath.zoomX(for: range.start, width: width, window: zoomWindow)
            let trailing = width - WaveformCropMath.zoomX(for: range.end, width: width, window: zoomWindow)
            let selectedWidth = width - leading - trailing

            ZStack(alignment: .leading) {
                // 1. 窓内の拡大波形（サンプルからリサンプル）
                Group {
                    if let samples {
                        let bucketCount = max(Int(width / 3), 16)
                        let slice = WaveformCropMath.resample(
                            samples,
                            in: zoomWindow,
                            sampleDuration: duration,
                            count: bucketCount
                        )
                        WaveformShape(samples: slice)
                            .fill(Color.accentColor.opacity(0.9))
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.1))
                            .overlay(ProgressView().scaleEffect(0.7))
                    }
                }
                .frame(width: width, height: zoomHeight)

                // 2. 選択範囲外のディム
                HStack(spacing: 0) {
                    Color.black.opacity(0.55).frame(width: max(leading, 0))
                    Color.clear.frame(width: max(selectedWidth, 0))
                    Color.black.opacity(0.55).frame(width: max(trailing, 0))
                }
                .frame(height: zoomHeight)
                .allowsHitTesting(false)

                // 3. 選択範囲の枠線
                Rectangle()
                    .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5)
                    .frame(width: max(selectedWidth, 0), height: zoomHeight)
                    .offset(x: leading)
                    .allowsHitTesting(false)

                // 4. ドラッグで窓移動 / タップでスクラブ
                zoomPanArea(width: width, range: range)

                // 5. 左右ハンドル（秒以下の微調整）
                zoomHandle(kind: .startZoom, x: leading)
                zoomHandle(kind: .endZoom, x: leading + selectedWidth)

                // 6. 再生ヘッド（窓内のみ）
                if previewer?.isPlaying == true, let previewer,
                   zoomWindow.contains(previewer.currentTime) {
                    let x = WaveformCropMath.zoomX(for: previewer.currentTime, width: width, window: zoomWindow)
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: 2.5, height: zoomHeight - 4)
                        .offset(x: x)
                        .shadow(color: .red.opacity(0.4), radius: 3)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: zoomSpace)
            .background(
                Color.clear
                    .onAppear { zoomWidth = width }
                    .onChange(of: width) { _, newWidth in zoomWidth = newWidth }
            )
        }
        .frame(height: zoomHeight)
    }

    /// 下段のドラッグでズーム窓を移動（panBaseWindow 基準・#36 と同じ累積対策）。
    /// 短いタップはスクラブ（タップ位置から再生）。
    private func zoomPanArea(width: CGFloat, range: TrimRange) -> some View {
        let tapThreshold: CGFloat = 8

        return Color.clear
            .frame(width: width, height: zoomHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(zoomSpace))
                    .onChanged { value in
                        guard abs(value.translation.width) >= tapThreshold else { return }
                        if draggingHandle != .panZoom {
                            draggingHandle = .panZoom
                            panBaseWindow = zoomWindow
                            previewer?.stop()
                        }
                        guard let base = panBaseWindow else { return }
                        zoomWindow = WaveformCropMath.pannedWindow(
                            base,
                            translationX: value.translation.width,
                            width: max(zoomWidth, 1),
                            duration: duration
                        )
                    }
                    .onEnded { value in
                        if draggingHandle == .panZoom {
                            draggingHandle = nil
                            panBaseWindow = nil
                        } else if let playURL, let previewer {
                            let time = WaveformCropMath.zoomTime(atX: value.location.x, width: max(zoomWidth, 1), window: zoomWindow)
                            let scrubTime = min(max(time, range.start), range.end)
                            previewer.play(url: playURL, from: scrubTime, to: range.end)
                        }
                    }
            )
    }

    /// 下段ハンドル。位置→時間の変換はズーム窓スケール（#76 の高精度調整）。
    /// ⚠️ `.frame` / `.contentShape` を `.offset` の前に（#36 原因1）
    private func zoomHandle(kind: Handle, x: CGFloat) -> some View {
        handleShape(isActive: draggingHandle == kind)
            .frame(width: handleWidth * 3, height: zoomHeight)
            .contentShape(Rectangle())
            .offset(x: x - handleWidth * 3 / 2)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(zoomSpace))
                    .onChanged { value in
                        if draggingHandle != kind {
                            draggingHandle = kind
                            previewer?.stop()
                        }
                        let target = WaveformCropMath.zoomTime(
                            atX: max(0, value.location.x),
                            width: max(zoomWidth, 1),
                            window: zoomWindow
                        )
                        switch kind {
                        case .startZoom:
                            startTime = currentRange.movingStart(to: target).start
                        case .endZoom:
                            endTime = currentRange.movingEnd(to: target).end
                        default:
                            break
                        }
                    }
                    .onEnded { _ in draggingHandle = nil }
            )
    }

    // MARK: - 共通パーツ

    private func timeLabels(range: TrimRange) -> some View {
        HStack {
            Text(formatTime(range.start))
            Spacer()
            Text(formatTime(range.width))
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatTime(range.end))
        }
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }

    private func handleShape(isActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(isActive ? Color.accentColor : Color.accentColor.opacity(0.85))
            .frame(width: handleWidth, height: nil)
            .frame(maxHeight: .infinity)
            .shadow(color: .black.opacity(0.3), radius: isActive ? 4 : 2)
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}