import SwiftUI
import AVFoundation

/// 動画トリム範囲選択バー。
/// サムネイル帯（filmstrip）＋ 左右ドラッグハンドル ＋ 選択範囲内でスクラブ。
///
/// - Design note: 範囲クランプは `TrimRange`（純粋関数）で毎フレーム適用する。
///   ジェスチャの後処理ではなく、`onChanged` のたびにクランプを挟むことで
///   不正な中間状態（end < start, 30秒超過）を画面上に露出させない。
struct VideoTrimmerBar: View {
    @Binding var startTime: Double
    @Binding var endTime: Double
    let videoURL: URL
    let videoDuration: Double
    let previewer: TrimPreviewer

    /// サムネイルのキャッシュ（filmstrip）。View のライフサイクルに紐づく
    @State private var thumbnails: [CGImage] = []

    /// ドラッグ中のハンドルを識別（ハンドルのスケール/Haptic 用）
    @State private var draggingHandle: Handle?

    /// パン開始時の範囲。累積移動量（translation）をこの基準に適用する。
    /// onChanged で currentRange を再計算して使うと、毎フレーム累積量が
    /// 既に動いた位置に足され二次関数的に加速する（#36 review の累積バグ）。
    @State private var panBaseRange: TrimRange?

    /// バーの描画幅（GeometryReader から取得）。座標→時間の変換に使う
    @State private var barWidth: CGFloat = 0

    private let barHeight: CGFloat = 48
    private let handleWidth: CGFloat = 6
    private let maxRangeSeconds: Double = 30
    private let thumbnailCount = 12
    private let coordinateSpaceName = "trimBar"

    enum Handle: Hashable { case start, end, pan }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let range = currentRange

            if !range.isValid {
                placeholderBar(width: width)
            } else {
                trimmerContent(width: width, range: range)
            }
        }
        .frame(height: barHeight + 24)
        .task(id: videoURL) {
            await generateThumbnails()
        }
    }

    // MARK: - Current Range

    private var currentRange: TrimRange {
        TrimRange(
            start: startTime,
            end: endTime,
            duration: videoDuration,
            maxRange: maxRangeSeconds
        )
    }

    // MARK: - Trim Content

    private func trimmerContent(width: CGFloat, range: TrimRange) -> some View {
        let startFraction = range.start / range.duration
        let endFraction = range.end / range.duration
        let leading = width * startFraction
        let trailing = width * (1 - endFraction)
        let selectedWidth = width * (endFraction - startFraction)

        return VStack(spacing: 4) {
            ZStack(alignment: .leading) {
                // 1. Filmstrip（サムネイル帯）
                filmstrip(width: width)

                // 2. 選択範囲外のディム
                HStack(spacing: 0) {
                    Color.black.opacity(0.55).frame(width: max(leading, 0))
                    Color.clear.frame(width: max(selectedWidth, 0))
                    Color.black.opacity(0.55).frame(width: max(trailing, 0))
                }

                // 3. 選択範囲の枠線
                Rectangle()
                    .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5)
                    .frame(width: max(selectedWidth, 0), height: barHeight)
                    .offset(x: leading)

                // 4. 選択範囲内タップでスクラブ（再生開始位置を指定）
                scrubArea(width: max(selectedWidth, 0), offset: leading, range: range)

                // 5. 左ハンドル（ドラッグ可能）
                startHandle(x: leading)

                // 6. 右ハンドル（ドラッグ可能）
                endHandle(x: leading + selectedWidth)

                // 7. 再生ヘッド（プレビュー中のみ）
                if previewer.isPlaying {
                    let playFraction = min(max(previewer.currentTime / range.duration, 0), 1)
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: 2.5, height: barHeight - 4)
                        .offset(x: width * playFraction)
                        .shadow(color: .red.opacity(0.4), radius: 3)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: coordinateSpaceName)
            .background(
                // width を State にミラーするための透明なトリガー
                Color.clear
                    .onAppear { barWidth = width }
                    .onChange(of: width) { _, newWidth in barWidth = newWidth }
            )

            // 時間ラベル
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
    }

    // MARK: - Filmstrip

    private func filmstrip(width: CGFloat) -> some View {
        Group {
            if thumbnails.isEmpty {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
                    .overlay(ProgressView().scaleEffect(0.7))
                    .frame(width: width, height: barHeight)
            } else {
                let thumbW = width / CGFloat(thumbnails.count)
                HStack(spacing: 0) {
                    ForEach(thumbnails.indices, id: \.self) { i in
                        Image(thumbnails[i], scale: 1.0, orientation: .up, label: Text("Frame"))
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: thumbW, height: barHeight)
                            .clipped()
                    }
                }
                .frame(width: width, height: barHeight)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    // MARK: - Scrub / Pan Area

    /// 選択範囲内の操作:
    /// - 短いタップ（minimumDistance 未満）→ スクラブ（再生位置指定）
    /// - ドラッグ（minimumDistance 以上）→ 選択範囲全体の平行移動
    ///
    /// タップとドラッグの切り分けは `DragGesture(minimumDistance:)` で行う。
    /// `onEnded` で `translation.width` が thresholds に満たなければタップ扱い（スクラブ）、
    /// そうでなければ移動量に応じて `TrimRange.movingRange(by:)` を適用する。
    private func scrubArea(width: CGFloat, offset: CGFloat, range: TrimRange) -> some View {
        let tapThreshold: CGFloat = 8

        return Color.clear
            .frame(width: width, height: barHeight)
            .offset(x: offset)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
                    .onChanged { value in
                        if abs(value.translation.width) >= tapThreshold {
                            if draggingHandle != .pan {
                                draggingHandle = .pan
                                // panBaseRange を1度だけ固定する。
                                // onChanged は毎回呼ばれるが、基準は変化させない。
                                panBaseRange = currentRange
                                previewer.stop()
                            }
                            // translation（ドラッグ開始からの累積移動量）を
                            // 固定した基準に適用する（currentRange ではない）。
                            let delta = value.translation.width / max(barWidth, 1) * videoDuration
                            let base = panBaseRange ?? currentRange
                            let clamped = base.movingRange(by: delta)
                            startTime = clamped.start
                            endTime = clamped.end
                        }
                    }
                    .onEnded { value in
                        if draggingHandle == .pan {
                            // 範囲移動だった → 終了
                            draggingHandle = nil
                            panBaseRange = nil
                        } else {
                            // タップだった → スクラブ（再生位置指定）
                            let fraction = (value.location.x - offset) / max(width, 1)
                            let scrubTime = range.start + min(max(fraction, 0), 1) * range.width
                            previewer.play(url: videoURL, from: scrubTime, to: range.end)
                        }
                    }
            )
    }

    // MARK: - Handles

    /// 左ハンドル: 開始位置をドラッグで移動。`coordinateSpace(.named)` で
    /// バー全体の座標系を取得し、`location.x` を時間に変換する。
    ///
    /// ⚠️ `.frame` / `.contentShape` を `.offset` より前に適用すること。
    /// `.offset` はレイアウト境界を変えないため、後に `.frame` を付けると
    /// 当たり判定が ZStack の x=0 に取り残される（#36 原因1）。
    private func startHandle(x: CGFloat) -> some View {
        handleShape(isActive: draggingHandle == .start)
            .frame(width: handleWidth * 3, height: barHeight)
            .contentShape(Rectangle())
            .offset(x: x - handleWidth * 3 / 2)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
                    .onChanged { value in
                        if draggingHandle != .start {
                            draggingHandle = .start
                            previewer.stop()
                        }
                        let target = max(0, value.location.x) / max(barWidth, 1) * videoDuration
                        let clamped = currentRange.movingStart(to: target)
                        startTime = clamped.start
                    }
                    .onEnded { _ in draggingHandle = nil }
            )
    }

    /// 右ハンドル: 終了位置をドラッグで移動。
    private func endHandle(x: CGFloat) -> some View {
        handleShape(isActive: draggingHandle == .end)
            .frame(width: handleWidth * 3, height: barHeight)
            .contentShape(Rectangle())
            .offset(x: x - handleWidth * 3 / 2)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
                    .onChanged { value in
                        if draggingHandle != .end {
                            draggingHandle = .end
                            previewer.stop()
                        }
                        let target = max(0, value.location.x) / max(barWidth, 1) * videoDuration
                        let clamped = currentRange.movingEnd(to: target)
                        endTime = clamped.end
                    }
                    .onEnded { _ in draggingHandle = nil }
            )
    }

    private func handleShape(isActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(isActive ? Color.accentColor : Color.accentColor.opacity(0.85))
            .frame(width: handleWidth, height: barHeight)
            .shadow(color: .black.opacity(0.3), radius: isActive ? 4 : 2)
    }

    private func placeholderBar(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.secondary.opacity(0.15))
            .frame(width: width, height: barHeight)
            .overlay(
                Text("no_video")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            )
    }

    // MARK: - Thumbnail Generation

    @MainActor
    private func generateThumbnails() async {
        thumbnails = []
        let asset = AVURLAsset(url: videoURL)
        guard let duration = try? await asset.load(.duration) else { return }
        let totalSeconds = CMTimeGetSeconds(duration)
        guard totalSeconds > 0 else { return }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // バーの高さに合わせてメモリ使用量を抑える
        generator.maximumSize = CGSize(width: 80, height: barHeight * 2)

        // 均等間隔で N 個のサムネイルを生成
        let interval = totalSeconds / Double(thumbnailCount)
        var images: [CGImage] = []
        for i in 0..<thumbnailCount {
            if Task.isCancelled { return }
            let time = CMTime(seconds: interval * Double(i), preferredTimescale: 600)
            do {
                // iOS 16+ の async API
                let cgImage = try await generator.image(at: time).image
                images.append(cgImage)
            } catch {
                // 単一フレームの失敗は無視（フィルムストリップに穴が開く程度で止めない）
            }
        }
        if !Task.isCancelled {
            thumbnails = images
        }
    }

    // MARK: - Formatting

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
