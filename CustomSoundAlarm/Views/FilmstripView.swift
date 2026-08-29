import SwiftUI
import AVFoundation

/// 動画サムネイルのフィルムストリップ（#77 の補助表示）。
/// 波形を主とし、通常の動画では位置の手がかりとして機能する。
/// 画面録画では絵が揃うため情報量は少ないが、廃止はしない。
///
/// #88: 「生成中」は明示的な `FilmstripState` で持ち、`thumbnails.isEmpty` で代用しない。
/// 映像トラックが無い素材（音声のみファイルなど）や生成結果0枚のときは
/// **領域ごと非表示**にする（空のグレー帯やスピナーを残さない）。
struct FilmstripView: View {
    let videoURL: URL
    var height: CGFloat = 36
    let thumbnailCount = 12

    @State private var thumbnails: [CGImage] = []
    @State private var state: FilmstripState = .loading

    var body: some View {
        GeometryReader { geo in
            Group {
                switch state {
                case .loading:
                    // 生成中のみスピナー（#88: 0枚で完了したらこの状態には戻らない）
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                        .overlay(ProgressView().scaleEffect(0.6))
                        .frame(width: geo.size.width, height: height)
                case .ready:
                    let thumbW = geo.size.width / CGFloat(thumbnails.count)
                    HStack(spacing: 0) {
                        ForEach(thumbnails.indices, id: \.self) { i in
                            Image(thumbnails[i], scale: 1.0, orientation: .up, label: Text("Frame"))
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: thumbW, height: height)
                                .clipped()
                        }
                    }
                    .frame(width: geo.size.width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                case .unavailable:
                    // 映像なし / 0枚 → 領域ごと非表示
                    EmptyView()
                }
            }
        }
        .frame(height: height)
        .task(id: videoURL) {
            await generateThumbnails()
        }
    }

    // MARK: - Thumbnail Generation

    @MainActor
    private func generateThumbnails() async {
        state = .loading
        thumbnails = []

        let asset = AVURLAsset(url: videoURL)

        // #88: まず映像トラックの有無を確認。音声のみの素材はサムネイルが
        // 生成できない（全フレーム失敗→空のまま）ため、生成前に切り上げる
        let videoTracks = try? await asset.loadTracks(withMediaType: .video)
        guard let videoTracks, !videoTracks.isEmpty else {
            state = FilmstripLogic.initialState(hasVideoTrack: false)
            return
        }
        state = FilmstripLogic.initialState(hasVideoTrack: true)

        guard let duration = try? await asset.load(.duration) else {
            // duration が取れない場合も生成の見込みが無い → 非表示で確定
            state = FilmstripLogic.finishState(generatedCount: 0)
            return
        }
        let totalSeconds = CMTimeGetSeconds(duration)
        guard totalSeconds > 0 else {
            state = FilmstripLogic.finishState(generatedCount: 0)
            return
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // バーの高さに合わせてメモリ使用量を抑える
        generator.maximumSize = CGSize(width: 80, height: height * 2)

        // 均等間隔で N 個のサムネイルを生成
        let interval = totalSeconds / Double(thumbnailCount)
        var images: [CGImage] = []
        for i in 0..<thumbnailCount {
            if Task.isCancelled { return }
            let time = CMTime(seconds: interval * Double(i), preferredTimescale: 600)
            do {
                let cgImage = try await generator.image(at: time).image
                images.append(cgImage)
            } catch {
                // 単一フレームの失敗は無視（フィルムストリップに穴が開く程度で止めない）
            }
        }

        guard !Task.isCancelled else { return }
        thumbnails = images
        // #88: 0枚で完了してもスピナーを止めて非表示にする
        state = FilmstripLogic.finishState(generatedCount: images.count)
    }
}