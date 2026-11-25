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

    /// ドラッグ開始時の範囲（ハンドル・pan とも、移動量は開始時の値に足す）
    @State private var dragBaseRange: TrimRange?
    /// 下段ハンドルのドラッグ開始時のズーム窓（移動量の時間換算に使う）
    @State private var dragBaseWindow: CropWindow?
    /// 端に当たった振動を、同じ端にいるあいだ繰り返さないための記録
    @State private var limitHitReason: LimitHitReason?
    /// つまみを掴んだ回数・端に当たった回数（`.sensoryFeedback` の trigger）
    @State private var handleGrabCount = 0
    @State private var limitHitCount = 0

    /// ピンチ拡大の基準窓と、指の中心にある時刻
    @State private var pinchBaseWindow: CropWindow?
    @State private var pinchAnchorTime: Double = 0
    @State private var isPinching = false
    /// ピンチの直後に、指を離した位置でスクラブ再生しないための印
    @State private var suppressScrubAfterPinch = false
    /// ピンチが始まったとき、同時に掴んでいたつまみ・範囲移動を止める印
    @State private var suppressHandleDrag = false
    @State private var suppressPanAfterPinch = false

    @State private var overviewWidth: CGFloat = 0
    @State private var zoomWidth: CGFloat = 0

    /// アクセント色のアセット解決に使う（#81-2）
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 目盛りラベルの幅と高さ（#237）。標準サイズでは従来と同じ 34 / 20。
    /// アクセシビリティサイズでは文字に合わせて広げ、下の開始・終了の行と重ねない。
    @ScaledMetric(relativeTo: .caption) private var rulerLabelWidth: CGFloat = 34
    @ScaledMetric(relativeTo: .caption) private var rulerHeight: CGFloat = 20

    // 最大の文字サイズでは、下の目盛りと時刻の行に高さを譲る（#237）
    private var overviewHeight: CGFloat { dynamicTypeSize.isAccessibilitySize ? 48 : 64 }
    private var zoomHeight: CGFloat { dynamicTypeSize.isAccessibilitySize ? 100 : 140 }
    /// つまみの見た目（#292）。枠の左右の辺そのもの。
    private let handleWidth: CGFloat = 16
    /// つまみの当たり判定。見た目 16pt の内側へ広げる（Apple の指針の最低 44pt）。
    private let handleHitWidth: CGFloat = 44
    private let frameLineWidth: CGFloat = 3
    private let frameCornerRadius: CGFloat = 10
    /// 再生ヘッドの幅（縁を含む・#303）
    private let playheadWidth: CGFloat = 12
    private let overviewSpace = "waveOverviewSpace"
    private let zoomSpace = "waveZoomSpace"
    /// 下段のサンプル解像度（600秒ファイルで窓8秒時に約100バケット）
    private let sampleCount = 8000

    /// 上段（全体波形）の縦スケール（#178）。
    ///
    /// DSWaveformImage の `LinearWaveformRenderer` は中心から**上下それぞれ**に
    /// `sample × 高さ × factor` を描く。つまり全高は最大で `2 × factor` 倍になる。
    /// 既定の 0.95 では最大 1.9 倍まで描かれ、音量の大きい音源で枠をはみ出す。
    /// 0.46 なら最大 0.92 倍に収まり、下段の `zoomWaveformCanvas`（0.92）とも揃う。
    static let overviewVerticalScalingFactor: CGFloat = 0.46

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
            )),
            verticalScalingFactor: Self.overviewVerticalScalingFactor
        )
    }

    enum Handle: Hashable {
        case startOverview, endOverview, panOverview
        case startZoom, endZoom, rangeZoom, panZoom
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
            // 下段の拡大率は変えず、再生の範囲だけ伝える（#303）
            previewer?.updateRange(currentRange)
        }
        .onChange(of: endTime) { _, _ in
            previewer?.updateRange(currentRange)
        }
        // 波形と選択範囲は時間軸なので、RTL でも左→右のまま（#149）。
        // ZStack(alignment: .leading) や offset が鏡像にならないよう固定する。
        .environment(\.layoutDirection, .leftToRight)
        // 掴んだ瞬間は軽い選択、最短・上限・音の端に当たった瞬間だけ impact（#292）
        .sensoryFeedback(.selection, trigger: handleGrabCount)
        .sensoryFeedback(.impact(weight: .light), trigger: limitHitCount)
    }

    private enum LimitHitReason: Equatable {
        case minimum
        case maxRange
        case audioEdge
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

    /// 触っている端が下段の窓の外に出たときだけ、窓を横にずらす（#303）。
    /// **窓の幅（拡大率）は変えない。**
    private func showEdge(_ edge: WaveformCropMath.CropEdge) {
        let time = edge == .start ? startTime : endTime
        zoomWindow = WaveformCropMath.window(
            showing: time,
            edge: edge,
            in: zoomWindow,
            duration: duration
        )
    }

    /// 再生の線を止めているときの位置（次に ▶ で鳴る位置・#303）。
    /// 鳴っている間は再生位置、止まっている間は残した位置。範囲の外なら開始。
    private func playheadTime(range: TrimRange) -> Double {
        guard let previewer else { return range.start }
        let time = previewer.currentTime
        return min(max(time, range.start), range.end)
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
        if !Task.isCancelled, zoomWindow.width <= 0 {
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

                // 3. 選択範囲の枠（太い角丸・#292）
                selectionFrame(
                    width: max(selectedWidth, 0),
                    height: overviewHeight,
                    offset: leading
                )

                // 4. 選択範囲内タップでスクラブ / ドラッグで範囲移動
                overviewScrubArea(width: max(selectedWidth, 0), offset: leading, range: range)

                // 5. 左右ハンドル（枠の内側・当たり判定 44pt）
                overviewHandle(
                    kind: .startOverview,
                    edge: .leading,
                    boundaryX: leading,
                    selectedWidth: selectedWidth
                )
                overviewHandle(
                    kind: .endOverview,
                    edge: .trailing,
                    boundaryX: leading + selectedWidth,
                    selectedWidth: selectedWidth
                )

                // 6. 再生ヘッド（縦線＋上下ノブ・#80-4）。つまみより手前に描く（#303）
                if previewer != nil {
                    let x = WaveformCropMath.overviewX(for: playheadTime(range: range), width: width, duration: duration)
                    playhead()
                        .offset(x: x - playheadWidth / 2)
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
    /// - 短いタップ → スクラブ（その位置からくり返し鳴らす）
    /// - ドラッグ → 選択範囲全体の平行移動（panBaseRange 基準・#36）
    /// どちらも鳴っている間は止めない（#303）。
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
                            panBaseWindow = zoomWindow
                        }
                        let delta = value.translation.width / max(overviewWidth, 1) * duration
                        let base = panBaseRange ?? currentRange
                        let clamped = base.movingRange(by: delta)
                        startTime = clamped.start
                        endTime = clamped.end
                        // 枠ごと動かした分だけ下段の窓も横にずらす（#303）。端で止まった分は数えない
                        if let baseWindow = panBaseWindow {
                            zoomWindow = WaveformCropMath.window(
                                shiftedBy: clamped.start - base.start,
                                in: baseWindow,
                                duration: duration
                            )
                        }
                    }
                    .onEnded { value in
                        if draggingHandle == .panOverview {
                            draggingHandle = nil
                            panBaseRange = nil
                            panBaseWindow = nil
                        } else if let playURL, let previewer {
                            // タップ → その位置からくり返し鳴らす
                            let time = WaveformCropMath.overviewTime(atX: value.location.x, width: max(overviewWidth, 1), duration: duration)
                            previewer.play(
                                url: playURL,
                                range: range,
                                from: min(max(time, range.start), range.end)
                            )
                        }
                    }
            )
    }

    /// 上段ハンドル。枠の内側に置き、当たり判定は内側へ 44pt 広げる（#292）。
    private func overviewHandle(
        kind: Handle,
        edge: HorizontalEdge,
        boundaryX: CGFloat,
        selectedWidth: CGFloat
    ) -> some View {
        cropHandle(
            kind: kind,
            edge: edge,
            boundaryX: boundaryX,
            selectedWidth: selectedWidth,
            height: overviewHeight,
            space: overviewSpace,
            secondsPerPoint: { _ in duration / max(overviewWidth, 1) }
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

                // 3. 選択範囲の枠（太い角丸・#292）
                selectionFrame(
                    width: max(selectedWidth, 0),
                    height: zoomHeight,
                    offset: leading
                )

                // 4. 枠の外のドラッグで窓移動 / タップでスクラブ
                zoomWindowPanArea(width: width, range: range)

                // 5. 枠の中（つまみ以外）のドラッグで範囲ごと移動
                zoomRangeArea(
                    width: max(selectedWidth, 0),
                    offset: leading,
                    range: range
                )

                // 6. 左右ハンドル（秒以下の微調整・枠の内側・当たり判定 44pt）
                // 窓の外に出た端は、窓の端に張り付いたつまみを出さない
                // （掴んだ瞬間に範囲が飛ぶのを防ぐ）。要素ごと出さないので、
                // 見えないつまみが読み上げや UI テストに出ることもない（#303）
                if range.start >= zoomWindow.start - 0.0001 {
                    zoomHandle(
                        kind: .startZoom,
                        edge: .leading,
                        boundaryX: leading,
                        selectedWidth: selectedWidth
                    )
                }
                if range.end <= zoomWindow.end + 0.0001 {
                    zoomHandle(
                        kind: .endZoom,
                        edge: .trailing,
                        boundaryX: leading + selectedWidth,
                        selectedWidth: selectedWidth
                    )
                }

                // 7. 再生ヘッド（縦線＋上下ノブ）。つまみより手前に描く（#303）
                if previewer != nil {
                    let x = WaveformCropMath.zoomX(for: playheadTime(range: range), width: width, window: zoomWindow)
                    playhead()
                        .offset(x: x - playheadWidth / 2)
                }
                }
                .coordinateSpace(name: zoomSpace)
                .background(
                    Color.clear
                        .onAppear { zoomWidth = width }
                        .onChange(of: width) { _, newWidth in zoomWidth = newWidth }
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("crop.zoomBar")
                .simultaneousGesture(pinchGesture)

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
            let color = Brand.orange

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

    /// 下段の下の時間目盛り（#80-5 / #81-3 / #87）。
    ///
    /// #87 の結合バグ修正:
    /// - 目盛り時刻は**絶対時刻**（`rulerTimes(in:step:)`・step の倍数に整列）。
    ///   以前は 0 基点の相対時刻を絶対座標変換（zoomX）に渡していたため、
    ///   窓が t=0 に無いとき全ラベルの x が負 → 左端にクランプされて重なっていた
    /// - ティックは時刻位置（tickX）に正確に置き、ラベルはティックの下に中心合わせで
    ///   置きつつ両端で内側にクランプする（clampedRulerX）。以前はティックも
    ///   ラベル幅のフレーム中央に置かれ半分ずれていた
    @ViewBuilder
    private func ruler(width: CGFloat) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            accessibilityRuler(width: width)
        } else {
            standardRuler(width: width)
        }
    }

    /// 最大の文字サイズ用: 窓の両端と中央の3つだけを等間隔に置く（#237）。
    /// 時刻の間引き計算に頼らず、ラベル同士が重ならないことを優先する。
    private func accessibilityRuler(width: CGFloat) -> some View {
        let times = [
            zoomWindow.start,
            zoomWindow.start + zoomWindow.width / 2,
            zoomWindow.end
        ]
        return ZStack(alignment: .topLeading) {
            ForEach(Array(times.enumerated()), id: \.offset) { index, t in
                let x = index == 0 ? 0 : (index == 1 ? width / 2 : width)
                Rectangle()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 1, height: 4)
                    .offset(x: x)
                    .allowsHitTesting(false)
            }
            HStack(spacing: 8) {
                ForEach(Array(times.enumerated()), id: \.offset) { index, t in
                    Text(WaveformCropMath.formatTime(t))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(
                            maxWidth: .infinity,
                            alignment: index == 0 ? .leading : (index == 2 ? .trailing : .center)
                        )
                        .accessibilityIdentifier("crop.ruler.\(WaveformCropMath.formatTime(t))")
                }
            }
            // 画面の端にラベルがくっつかないよう、最大文字のときだけ少し内側に置く（#237）
            .padding(.horizontal, 4)
            .offset(y: 6)
        }
        .frame(width: width, height: rulerHeight, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func standardRuler(width: CGFloat) -> some View {
        let span = zoomWindow.width
        let labelWidth = Double(rulerLabelWidth)
        let step = WaveformCropMath.rulerStep(
            forSpan: span,
            barWidth: width,
            labelWidth: labelWidth
        )
        let times = WaveformCropMath.rulerTimes(in: zoomWindow, step: step)

        return ZStack(alignment: .topLeading) {
            ForEach(times, id: \.self) { t in
                let tickX = WaveformCropMath.zoomX(for: t, width: width, window: zoomWindow)
                // ラベル中心 = ティック位置。両端ではみ出す分だけ内側にクランプ
                let labelCenter = WaveformCropMath.clampedRulerX(
                    x: tickX - labelWidth / 2,
                    barWidth: width,
                    labelWidth: labelWidth
                ) + labelWidth / 2

                ZStack(alignment: .top) {
                    // ティック: 時刻位置に正確に
                    Rectangle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: 1, height: 4)
                        .offset(x: tickX)
                    // ラベル: ティックの下・中心合わせ（両端でクランプ済み）
                    Text(WaveformCropMath.formatTime(t))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize()
                        .frame(width: labelWidth, alignment: .center)
                        .offset(x: labelCenter - labelWidth / 2, y: 6)
                        .accessibilityIdentifier("crop.ruler.\(WaveformCropMath.formatTime(t))")
                }
            }
        }
        .frame(width: width, height: rulerHeight, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    /// 下段のドラッグでズーム窓を移動（panBaseWindow 基準・#36 と同じ累積対策）。
    /// 短いタップはスクラブ（タップ位置からくり返し鳴らす）。再生は止めない（#303）。
    private func zoomWindowPanArea(width: CGFloat, range: TrimRange) -> some View {
        let tapThreshold: CGFloat = 8

        return Color.clear
            .frame(width: width, height: zoomHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(zoomSpace))
                    .onChanged { value in
                        guard !isPinching, !suppressPanAfterPinch else { return }
                        if draggingHandle == nil {
                            // ピンチの後の最初の1本指は、新しい操作として扱う
                            suppressScrubAfterPinch = false
                        }
                        guard abs(value.translation.width) >= tapThreshold else { return }
                        if draggingHandle != .panZoom {
                            draggingHandle = .panZoom
                            panBaseWindow = zoomWindow
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
                        suppressPanAfterPinch = false
                        if draggingHandle == .panZoom {
                            draggingHandle = nil
                            panBaseWindow = nil
                        } else if !isPinching, !suppressScrubAfterPinch,
                                  let playURL, let previewer {
                            let time = WaveformCropMath.zoomTime(atX: value.location.x, width: max(zoomWidth, 1), window: zoomWindow)
                            previewer.play(
                                url: playURL,
                                range: range,
                                from: min(max(time, range.start), range.end)
                            )
                        }
                    }
            )
    }

    /// 下段の枠の中（つまみ以外）のドラッグで、選択範囲ごと動かす（#292）。
    /// 短いタップはスクラブ（タップ位置からくり返し鳴らす）。再生は止めない（#303）。
    private func zoomRangeArea(width: CGFloat, offset: CGFloat, range: TrimRange) -> some View {
        let tapThreshold: CGFloat = 8

        return Color.clear
            .frame(width: width, height: zoomHeight)
            .contentShape(Rectangle())
            .offset(x: offset)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(zoomSpace))
                    .onChanged { value in
                        guard !isPinching, !suppressHandleDrag else { return }
                        guard abs(value.translation.width) >= tapThreshold else { return }
                        if draggingHandle != .rangeZoom {
                            draggingHandle = .rangeZoom
                            dragBaseRange = currentRange
                            dragBaseWindow = zoomWindow
                        }
                        guard let base = dragBaseRange else { return }
                        let window = dragBaseWindow ?? zoomWindow
                        let delta = value.translation.width / max(zoomWidth, 1) * window.width
                        let clamped = base.movingRange(by: Double(delta))
                        startTime = clamped.start
                        endTime = clamped.end
                        // 枠ごと動かしたときは開始の端の規則に従う（#303）
                        showEdge(.start)
                    }
                    .onEnded { value in
                        if draggingHandle == .rangeZoom {
                            draggingHandle = nil
                            dragBaseRange = nil
                            dragBaseWindow = nil
                            suppressHandleDrag = false
                        } else if !isPinching, !suppressScrubAfterPinch, !suppressHandleDrag,
                                  let playURL, let previewer {
                            let time = WaveformCropMath.zoomTime(atX: value.location.x, width: max(zoomWidth, 1), window: zoomWindow)
                            previewer.play(
                                url: playURL,
                                range: range,
                                from: min(max(time, range.start), range.end)
                            )
                        }
                    }
            )
    }

    /// 下段ハンドル。位置→時間の変換はズーム窓スケール（#76 の高精度調整）。
    private func zoomHandle(
        kind: Handle,
        edge: HorizontalEdge,
        boundaryX: CGFloat,
        selectedWidth: CGFloat
    ) -> some View {
        cropHandle(
            kind: kind,
            edge: edge,
            boundaryX: boundaryX,
            selectedWidth: selectedWidth,
            height: zoomHeight,
            space: zoomSpace,
            secondsPerPoint: { window in
                (window ?? zoomWindow).width / max(zoomWidth, 1)
            }
        )
    }

    /// 2本指のピンチで拡大・縮小（#292・拡大表示の下段）。
    private var pinchGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0)
            .onChanged { value in
                if pinchBaseWindow == nil {
                    guard abs(value.magnification - 1) > 0.001 else { return }
                    isPinching = true
                    suppressScrubAfterPinch = true
                    pinchBaseWindow = zoomWindow
                    pinchAnchorTime = zoomWindow.start
                        + Double(value.startAnchor.x) * zoomWindow.width
                    switch draggingHandle {
                    case .startOverview, .startZoom, .endOverview, .endZoom, .rangeZoom:
                        // 2本目の指がつまみ・枠に触れただけのときは、範囲を動かさない
                        if let base = dragBaseRange {
                            startTime = base.start
                            endTime = base.end
                        }
                        draggingHandle = nil
                        dragBaseRange = nil
                        dragBaseWindow = nil
                        limitHitReason = nil
                        suppressHandleDrag = true
                    case .panZoom:
                        if let base = panBaseWindow {
                            zoomWindow = base
                        }
                        draggingHandle = nil
                        panBaseWindow = nil
                        suppressPanAfterPinch = true
                    default:
                        break
                    }
                }
                guard let base = pinchBaseWindow else { return }
                // 指の位置を中心に拡大・縮小するだけ。窓を選択範囲へ寄せない（#303）
                zoomWindow = WaveformCropMath.zoomedWindow(
                    base,
                    magnification: value.magnification,
                    anchorTime: pinchAnchorTime,
                    duration: duration
                )
            }
            .onEnded { _ in
                pinchBaseWindow = nil
                isPinching = false
            }
    }

    // MARK: - 共通パーツ

    /// 選択範囲の枠（上下 3pt・角丸 10・不透明のブランド色・#292）。
    private func selectionFrame(width: CGFloat, height: CGFloat, offset: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: frameCornerRadius, style: .continuous)
            .strokeBorder(Brand.orange, lineWidth: frameLineWidth)
            .frame(width: max(width, 0), height: height)
            .offset(x: offset)
            .allowsHitTesting(false)
    }

    /// 枠の内側に付くつまみ（見た目 16pt・当たり判定 44pt・#292）。
    ///
    /// - 見た目は枠の左右の辺そのもの。外側の角だけ枠に合わせて丸める
    /// - 当たり判定は範囲の内側へ広げる。端が画面端でも全部画面内に残る
    /// - 範囲が狭く 44pt どうしが重なるときは、選択範囲を半分に分ける
    ///   （触れた場所に近い側のつまみが動く）
    private func cropHandle(
        kind: Handle,
        edge: HorizontalEdge,
        boundaryX: CGFloat,
        selectedWidth: CGFloat,
        height: CGFloat,
        space: String,
        secondsPerPoint: @escaping (CropWindow?) -> Double
    ) -> some View {
        let safeSelectedWidth = max(selectedWidth, 0)
        // 44pt どうしが重なるときは選択範囲を半分に分ける（触れた側が動く）
        let hitWidth = min(handleHitWidth, safeSelectedWidth / 2)
        let hitOffset = edge == .leading
            ? boundaryX
            : boundaryX - hitWidth
        let visualWidth = min(handleWidth, hitWidth)
        let visualOffset = edge == .leading
            ? 0
            : hitWidth - visualWidth
        let side = (kind == .startOverview || kind == .startZoom) ? "start" : "end"
        let tier = (kind == .startOverview || kind == .endOverview) ? "overview" : "zoom"

        return ZStack(alignment: .leading) {
            cropHandleShape(edge: edge, width: visualWidth, height: height)
                .frame(width: visualWidth, height: height)
                .offset(x: visualOffset)
                .allowsHitTesting(false)
        }
        .frame(width: hitWidth, height: height, alignment: .leading)
        .contentShape(Rectangle())
        .offset(x: hitOffset)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
                .onChanged { value in
                    guard !isPinching, !suppressHandleDrag else { return }
                    if draggingHandle != kind {
                        draggingHandle = kind
                        dragBaseRange = currentRange
                        dragBaseWindow = zoomWindow
                        limitHitReason = nil
                        handleGrabCount += 1
                    }
                    guard let base = dragBaseRange else { return }
                    let delta = Double(value.translation.width) * secondsPerPoint(dragBaseWindow)
                    switch kind {
                    case .startOverview, .startZoom:
                        let desired = base.start + delta
                        startTime = base.movingStart(to: desired).start
                        noteLimitHit(for: kind, base: base, desired: desired)
                        showEdge(.start)
                    case .endOverview, .endZoom:
                        let desired = base.end + delta
                        endTime = base.movingEnd(to: desired).end
                        noteLimitHit(for: kind, base: base, desired: desired)
                        showEdge(.end)
                    case .panOverview, .rangeZoom, .panZoom:
                        break
                    }
                }
                .onEnded { _ in
                    let movedStart = draggingHandle == .startOverview || draggingHandle == .startZoom
                    draggingHandle = nil
                    dragBaseRange = nil
                    dragBaseWindow = nil
                    limitHitReason = nil
                    suppressHandleDrag = false
                    // 開始を離したら、新しい開始から鳴り直す（#303）。
                    // 30秒の範囲だと次の周回まで待つことになるため。
                    if movedStart, let playURL, let previewer, previewer.isPlaying {
                        previewer.play(url: playURL, range: currentRange, from: startTime)
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(side == "start" ? "time_start" : "time_end"))
        .accessibilityIdentifier("crop.handle.\(side).\(tier)")
    }

    /// つまみの見た目。外側（枠の端）だけ角丸 10 の連続カーブにする。
    private func cropHandleShape(edge: HorizontalEdge, width: CGFloat, height: CGFloat) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: edge == .leading ? frameCornerRadius : 0,
            bottomLeadingRadius: edge == .leading ? frameCornerRadius : 0,
            bottomTrailingRadius: edge == .trailing ? frameCornerRadius : 0,
            topTrailingRadius: edge == .trailing ? frameCornerRadius : 0,
            style: .continuous
        )
        .fill(Brand.orange)
        .overlay {
            Image(systemName: edge == .leading ? "chevron.compact.left" : "chevron.compact.right")
                .resizable()
                .scaledToFit()
                .frame(width: max(0, min(handleWidth * 0.75, width - 4)), height: height * 0.4)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
        }
    }

    /// ハンドルが最短・上限・音の端に当たった瞬間だけ振動させる（#292）。
    /// 同じ端にいるあいだは繰り返さない。
    private func noteLimitHit(for kind: Handle, base: TrimRange, desired: Double) {
        let reason: LimitHitReason?
        switch kind {
        case .startOverview, .startZoom:
            if desired > base.start {
                if desired >= base.end {
                    reason = .minimum
                } else if base.end - desired >= base.maxRange {
                    reason = .maxRange
                } else {
                    reason = nil
                }
            } else if desired < base.start {
                if desired <= 0 {
                    reason = .audioEdge
                } else if base.end - desired >= base.maxRange {
                    reason = .maxRange
                } else {
                    reason = nil
                }
            } else {
                reason = nil
            }
        case .endOverview, .endZoom:
            if desired > base.end {
                if desired >= duration {
                    reason = .audioEdge
                } else if desired - base.start >= base.maxRange {
                    reason = .maxRange
                } else {
                    reason = nil
                }
            } else if desired < base.end {
                if desired <= base.start {
                    reason = .minimum
                } else {
                    reason = nil
                }
            } else {
                reason = nil
            }
        case .panOverview, .rangeZoom, .panZoom:
            reason = nil
        }

        if let reason, reason != limitHitReason {
            limitHitCount += 1
        }
        limitHitReason = reason
    }

    /// 再生ヘッド: 縦線＋上下の丸ノブ（#80-4 / #303）。
    ///
    /// - 線は `Color.primary`（明るい画面で黒・暗い画面で白）・太さ 2pt
    /// - 外側に背景色の縁を 1.5pt 付け、オレンジのつまみの上でも見えるようにする
    /// - 幅 `playheadWidth` で、中心が再生位置に来るよう呼び出し側で offset する
    private func playhead() -> some View {
        ZStack {
            playheadShape(circleDiameter: 12, lineWidth: 5, color: Color.warmListBackground)
            playheadShape(circleDiameter: 9, lineWidth: 2, color: Color.primary)
        }
        .frame(width: playheadWidth)
        .allowsHitTesting(false)
    }

    private func playheadShape(circleDiameter: CGFloat, lineWidth: CGFloat, color: Color) -> some View {
        VStack(spacing: 0) {
            Circle()
                .frame(width: circleDiameter, height: circleDiameter)
            Rectangle()
                .fill(color)
                .frame(width: lineWidth)
            Circle()
                .frame(width: circleDiameter, height: circleDiameter)
        }
        .frame(maxHeight: .infinity)
        .foregroundStyle(color)
    }

    /// 4つの値をラベル付きで明示（#79-6: どれが何か分からない状態を解消する）
    @ViewBuilder
    private func timeLabels(range: TrimRange) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            // 最大の文字サイズでは2×2に分け、1列あたりの幅を確保する（#237）
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                GridRow {
                    labeledTime("time_start", value: range.start, identifier: "crop.time.start")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    labeledTime("time_end", value: range.end, identifier: "crop.time.end")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                GridRow {
                    labeledTime("time_length", value: range.width, identifier: "crop.time.length")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    labeledTime("time_total", value: duration, identifier: "crop.time.total")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 8) {
                labeledTime("time_start", value: range.start, identifier: "crop.time.start")
                Spacer(minLength: 0)
                labeledTime("time_end", value: range.end, identifier: "crop.time.end")
                Spacer(minLength: 0)
                labeledTime("time_length", value: range.width, identifier: "crop.time.length")
                Spacer(minLength: 0)
                labeledTime("time_total", value: duration, identifier: "crop.time.total")
            }
        }
    }

    private func labeledTime(
        _ key: LocalizedStringKey,
        value: Double,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key)
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
            Text(WaveformCropMath.formatTime(value))
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

}