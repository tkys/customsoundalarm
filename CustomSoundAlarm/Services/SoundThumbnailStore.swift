import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import UIKit
import os

/// 音源サムネイルの生成・保存（#86）。
///
/// - 保存先: `Library/Thumbnails`（小さな JPEG・数十KB・音源削除時に一緒に消す）
/// - 生成元: 動画は12枚のフレーム候補から**輝度分散が最大の1枚**を自動選択
///   （暗転・無地を避ける。FilmstripView と同じ AVAssetImageGenerator の使い方）。
///   音声は埋め込みアートワーク（ID3 / MP4 メタデータ）。
/// - 選択の優先順位や分散計算は `SoundThumbnailLogic`（純粋関数）が担う
@MainActor
final class SoundThumbnailStore {
    static let shared = SoundThumbnailStore()

    private let logger = Logger(subsystem: "com.tkysdev.customsoundalarm", category: "SoundThumbnail")

    /// メモリキャッシュ（一覧のスクロールで毎回ディスクを読まない）
    private let cache = NSCache<NSString, UIImage>()

    /// サムネイルの保存ディレクトリ
    var thumbnailsDirectory: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let dir = library.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {}

    // MARK: - 読み書き

    /// 保存済みサムネイルの読み込み（キャッシュ優先）。失敗は nil
    func image(fileName: String) -> UIImage? {
        if let cached = cache.object(forKey: fileName as NSString) {
            return cached
        }
        let url = thumbnailsDirectory.appendingPathComponent(fileName)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: fileName as NSString)
        return image
    }

    /// CGImage を JPEG として保存し、ファイル名を返す（失敗は nil）。
    /// 一辺 ~300px・品質0.7 で数十KBに収める
    @discardableResult
    func save(_ image: CGImage) -> String? {
        let resized = Self.resized(image, maxDimension: 300)
        let fileName = "\(UUID().uuidString).jpg"
        let url = thumbnailsDirectory.appendingPathComponent(fileName)

        let uiImage = UIImage(cgImage: resized)
        guard let data = uiImage.jpegData(compressionQuality: 0.7) else { return nil }
        do {
            try data.write(to: url)
            cache.setObject(uiImage, forKey: fileName as NSString)
            return fileName
        } catch {
            logger.error("Failed to write thumbnail: \(error.localizedDescription)")
            return nil
        }
    }

    /// サムネイルファイルを削除（音源削除時に呼ぶ）
    func delete(fileName: String) {
        cache.removeObject(forKey: fileName as NSString)
        let url = thumbnailsDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - 動画フレーム

    /// 動画から12枚のフレーム候補を生成し、輝度分散が最大の1枚を返す（#86）。
    /// 映像トラックが無い素材は nil
    func bestVideoFrame(from videoURL: URL) async -> CGImage? {
        let asset = AVURLAsset(url: videoURL)
        guard let videoTracks = try? await asset.loadTracks(withMediaType: .video),
              !videoTracks.isEmpty else {
            return nil
        }
        guard let duration = try? await asset.load(.duration) else { return nil }
        let totalSeconds = CMTimeGetSeconds(duration)
        guard totalSeconds > 0 else { return nil }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 300, height: 300)

        // 均等間隔で12枚生成（FilmstripView と同じ構成）
        let count = 12
        var frames: [CGImage] = []
        let interval = totalSeconds / Double(count)
        for i in 0..<count {
            if Task.isCancelled { return nil }
            let time = CMTime(seconds: interval * Double(i), preferredTimescale: 600)
            if let frame = try? await generator.image(at: time).image {
                frames.append(frame)
            }
        }
        guard !frames.isEmpty else { return nil }

        // 輝度分散が最大 = 暗転・無地でない フレームを自動選択
        let variances = frames.map { SoundThumbnailLogic.variance(samples: Self.luminanceSamples(of: $0)) }
        guard let best = SoundThumbnailLogic.bestFrameIndex(variances: variances) else { return nil }
        return frames[best]
    }

    // MARK: - アートワーク

    /// 音声ファイルの埋め込みアートワーク（ID3 / MP4 メタデータ）を返す。無ければ nil
    func artwork(from audioURL: URL) async -> CGImage? {
        let asset = AVURLAsset(url: audioURL)
        guard let metadata = try? await asset.load(.metadata) else { return nil }
        let items = AVMetadataItem.metadataItems(
            from: metadata,
            filteredByIdentifier: .commonIdentifierArtwork
        )
        guard let item = items.first else { return nil }

        let data: Data?
        if let dataValue = item.dataValue {
            data = dataValue
        } else if let rawValue = item.value as? Data {
            data = rawValue
        } else {
            data = nil
        }
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return image
    }

    // MARK: - Private

    /// 画像を輝度の標本配列にdownsampleする（32x32 グレースケール）
    static func luminanceSamples(of image: CGImage) -> [Double] {
        let side = 32
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return []
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let buffer = context.data else { return [] }
        let pixels = buffer.bindMemory(to: UInt8.self, capacity: side * side)
        return (0..<(side * side)).map { Double(pixels[$0]) / 255.0 }
    }

    /// 長辺を maxDimension に収めるリサイズ（同一サイズ以下ならそのまま）
    static func resized(_ image: CGImage, maxDimension: Int) -> CGImage {
        let width = image.width
        let height = image.height
        let longest = max(width, height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = Double(maxDimension) / Double(longest)
        let newWidth = max(1, Int(Double(width) * scale))
        let newHeight = max(1, Int(Double(height) * scale))

        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return image
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage() ?? image
    }
}