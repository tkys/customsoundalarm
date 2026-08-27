import SwiftUI
import AVFoundation

/// 動画サムネイルのフィルムストリップ（#77 の補助表示）。
/// 波形を主とし、通常の動画では位置の手がかりとして機能する。
/// 画面録画では絵が揃うため情報量は少ないが、廃止はしない。
struct FilmstripView: View {
    let videoURL: URL
    var height: CGFloat = 36
    let thumbnailCount = 12

    @State private var thumbnails: [CGImage] = []

    var body: some View {
        GeometryReader { geo in
            Group {
                if thumbnails.isEmpty {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                        .overlay(ProgressView().scaleEffect(0.6))
                        .frame(width: geo.size.width, height: height)
                } else {
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
        thumbnails = []
        let asset = AVURLAsset(url: videoURL)
        guard let duration = try? await asset.load(.duration) else { return }
        let totalSeconds = CMTimeGetSeconds(duration)
        guard totalSeconds > 0 else { return }

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
        if !Task.isCancelled {
            thumbnails = images
        }
    }
}