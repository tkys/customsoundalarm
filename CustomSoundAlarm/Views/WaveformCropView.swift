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

    /// アクセント色のアセット解決に使う（#81-2）
    @Environment(\.colorScheme) private var colorScheme

    private let overviewHeight: CGFloat = 64
    private let zoomHeight: CGFloat = 140
    private let rulerHeight: CGFloat = 20
    private let handleWidth: CGFloat = 6
    private let overviewSpace = "waveOverviewSpace"
    private let zoomSpace = "waveZoomSpace"
    /// 下段のサンプル解像度（600秒ファイルで窓8秒時に約100バケット）
    private let sampleCount = 8000

    /// 上段（WaveformView）用のストライプ設定（#80-2）。スケールはビュー側既定。
    /// 色は AccentColor アセットを直接解決（#81-2: UIColor(Color.accentColor) は
    /// 環境依存のためビュー階層の外で青にフォールバックする）
    private var stripedOverviewConfig: Waveform.Configuration {
        Waveform.Configuration(
            style: .striped(.init(
                color: Brand.accentUIColor(dark: colorScheme == .dark),
                width: 2,
                spacing: 2,
                lineCap: .round
            ))
        )
    }

    enum Handle: Hashable {
        case startOverview, endOverview, panOverview
        case startZoom, endZoom, panZoom
    }

    var body: some View {
        let range = currentRange
        VStack(spacing: 10) {
            // テキスト行は横パディングあり（#81-3）。全画面幅にするのは波形のみ
            bigTimeLabel(range: range)
                .padding(.horizontal, 20)
            overviewBar(range: range)
            zoomBar(range: range)
            timeLabels(range: range)
                .padding(.horizontal, 20)
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
        // 再生位置にズーム窓を追従させる（#79 バグ2: 再生ヘッドが窓外に出たら再配置）
        .onChange(of: previewer?.currentTime) { _, playhead in
            guard let playhead, previewer?.isPlaying == true else { return }
            zoomWindow = WaveformCropMath.windowFollowingPlayback(
                current: zoomWindow,
                playhead: playhead,
                duration: duration
            )
        }
    }

    // MARK: - 主役の現在時刻（#80-3）

    /// 再生位置を1/100秒まで大きな数字で表示する。
    /// 非再生時は再生開始位置（選択の先頭）を示す
    private func bigTimeLabel(range: TrimRange) -> some View {
        let displayTime: Double
        if let previewer, previewer.isPlaying {
            displayTime = previewer.currentTime
        } else {
            displayTime = range.start
        }
        return Text(WaveformCropMath.formatPreciseTime(displayTime))
            .font(.system(size: 34, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
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
        // ⚠️ WaveformAnalyzer の戻り値は 1 = 無音(-50dB) の反転正規化（#83）。
        // レベル値への変換は resample が担う（生値を直接 UI に使わないこと）。
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
                // 1. 全体波形（ストライプ表現・#80-2。読み込み中は自前のプレースホルダ）
                ZStack {
                    WaveformView(audioURL: audioURL, configuration: stripedOverviewConfig)
                    if samples == nil {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: width, height: overviewHeight)
                            .background(Color.warmListBackground)
                    }
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

                // 6. 再生ヘッド（縦線＋上下ノブ・#80-4）
                if previewer?.isPlaying == true, let previewer {
                    let x = WaveformCropMath.overviewX(for: previewer.currentTime, width: width, duration: duration)
                    playhead()
                        .offset(x: x - 5)
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
            .contentShape(Rectangle())
            .offset(x: offset)
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

            VStack(spacing: 2) {
                ZStack(alignment: .leading) {
                    // 1. 窓内の拡大波形（自前 Canvas 描画・#81-1 / #82-1）
                    // バケット数＝バー本数（zoomBucketCount）で **1バケット＝1バー**。
                    // slice[i] をそのまま描き、再集約しない（ピークのピーク取りは飽和の原因）
                    Group {
                        if let samples {
                            let slice = WaveformCropMath.resample(
                                samples,
                                in: zoomWindow,
                                sampleDuration: duration,
                                count: WaveformCropMath.zoomBucketCount(viewWidth: width)
                            )
                            zoomWaveformCanvas(slice: slice, width: width)
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

                // 6. 再生ヘッド（縦線＋上下ノブ・窓の追従により常に窓内）
                if previewer?.isPlaying == true, let previewer {
                    let x = WaveformCropMath.zoomX(for: previewer.currentTime, width: width, window: zoomWindow)
                    playhead()
                        .offset(x: x - 5)
                }
                }
                .coordinateSpace(name: zoomSpace)
                .background(
                    Color.clear
                        .onAppear { zoomWidth = width }
                        .onChange(of: width) { _, newWidth in zoomWidth = newWidth }
                )

                // 7. 時間目盛り（ズーム窓の絶対時刻・#80-5）
                ruler(width: width)
            }
        }
        .frame(height: zoomHeight + rulerHeight)
    }

    /// 下段の波形を Canvas で描く（#81-1 / #82-1 / #83）。
    /// 4ptピッチ（幅2+間隔2）の角丸縦バーを上下対称（中央揃え）に並べる。
    /// **1バケット＝1バー**（slice[i] をそのまま使用・再集約しない）。
    ///
    /// ⚠️ `slice` は `resample` が既に **0 = 無音・1 = 最大音量のレベル値**に変換済み
    /// （DSWaveformImage の生サンプルは 1 = 無音の反転正規化。#83）。
    /// ここで反転してはならない。ピッチは zoomBucketCount の既定値（4）と一致させること。
    private func zoomWaveformCanvas(slice: [Float], width: CGFloat) -> some View {
        Canvas { context, size in
            let barWidth: CGFloat = 2
            let pitch: CGFloat = 4  // barWidth + spacing（zoomBucketCount の barPitch と同じ）
            let midY = size.height / 2
            let color = Color.accentColor

            for (i, level) in slice.enumerated() {
                let x = CGFloat(i) * pitch
                guard x + barWidth <= size.width else { break }
                let barHeight = max(2, CGFloat(level) * size.height * 0.92)
                let rect = CGRect(x: x, y: midY - barHeight / 2, width: barWidth, height: barHeight)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(color)
                )
            }
        }
        .frame(width: width, height: zoomHeight)
    }

    /// 下段の下の時間目盛り（#80-5 / #81-3）。
    /// ラベルの実描画幅を考慮して刻みを間引き、両端で内側にクランプする
    private func ruler(width: CGFloat) -> some View {
        let span = zoomWindow.width
        let labelWidth: Double = 34
        let step = WaveformCropMath.rulerStep(
            forSpan: span,
            barWidth: width,
            labelWidth: labelWidth
        )
        let times = WaveformCropMath.rulerTimes(span: span, step: step)

        return ZStack(alignment: .leading) {
            ForEach(times, id: \.self) { t in
                let rawX = WaveformCropMath.zoomX(for: t, width: width, window: zoomWindow)
                let x = WaveformCropMath.clampedRulerX(x: rawX, barWidth: width, labelWidth: labelWidth)
                VStack(spacing: 2) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: 1, height: 4)
                    Text(WaveformCropMath.formatTime(t))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                .frame(width: labelWidth, alignment: .center)
                .offset(x: x)
            }
        }
        .frame(width: width, height: rulerHeight, alignment: .topLeading)
        .allowsHitTesting(false)
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

    /// 再生ヘッド: 縦線＋上下の丸ノブ（#80-4）。アクセント色・掴める感のある形状。
    /// 幅10ptで、中心が再生位置に来るよう呼び出し側で offset(x: x - 5) する
    private func playhead() -> some View {
        VStack(spacing: 0) {
            Circle()
                .frame(width: 9, height: 9)
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 2)
            Circle()
                .frame(width: 9, height: 9)
        }
        .frame(width: 10)
        .foregroundStyle(Color.accentColor)
        .shadow(color: Color.accentColor.opacity(0.35), radius: 3)
        .allowsHitTesting(false)
    }

    /// 4つの値をラベル付きで明示（#79-6: どれが何か分からない状態を解消する）
    private func timeLabels(range: TrimRange) -> some View {
        HStack(spacing: 8) {
            labeledTime("time_start", value: range.start)
            Spacer(minLength: 0)
            labeledTime("time_end", value: range.end)
            Spacer(minLength: 0)
            labeledTime("time_length", value: range.width)
            Spacer(minLength: 0)
            labeledTime("time_total", value: duration)
        }
    }

    private func labeledTime(_ key: LocalizedStringKey, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(key)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(WaveformCropMath.formatTime(value))
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
    }

    private func handleShape(isActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(isActive ? Color.accentColor : Color.accentColor.opacity(0.85))
            .frame(width: handleWidth, height: nil)
            .frame(maxHeight: .infinity)
            .shadow(color: .black.opacity(0.3), radius: isActive ? 4 : 2)
    }
}