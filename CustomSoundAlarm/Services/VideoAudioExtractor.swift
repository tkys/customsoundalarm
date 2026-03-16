import Foundation
import AVFoundation
import os

/// 動画ファイルから音声トラックを抽出する
@MainActor
final class VideoAudioExtractor {
    static let shared = VideoAudioExtractor()

    private let logger = Logger(subsystem: "com.tkysdev.customsoundalarm", category: "VideoAudioExtractor")

    private init() {}

    /// 動画から音声を抽出し、一時M4Aファイルとして返す
    /// - Parameters:
    ///   - videoURL: 動画ファイルのURL
    ///   - startTime: トリム開始時間（秒）
    ///   - endTime: トリム終了時間（秒）
    /// - Returns: 抽出された一時音声ファイルのURL
    func extractAudio(
        from videoURL: URL,
        startTime: Double = 0,
        endTime: Double? = nil
    ) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)

        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)

        guard totalSeconds > 0 else {
            throw VideoExtractionError.noAudioTrack
        }

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw VideoExtractionError.noAudioTrack
        }

        let actualEnd = min(endTime ?? totalSeconds, totalSeconds)
        let start = CMTime(seconds: startTime, preferredTimescale: 600)
        let end = CMTime(seconds: actualEnd, preferredTimescale: 600)
        let timeRange = CMTimeRange(start: start, end: end)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw VideoExtractionError.exportSessionFailed
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).m4a")

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.timeRange = timeRange

        await exportSession.export()

        guard exportSession.status == .completed else {
            throw VideoExtractionError.exportFailed(
                exportSession.error?.localizedDescription ?? String(localized: "error_unknown")
            )
        }

        logger.info("Extracted audio: \(actualEnd - startTime)s from video")
        return outputURL
    }

    /// 動画の総再生時間を取得
    func getDuration(from url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }
}

enum VideoExtractionError: LocalizedError {
    case noAudioTrack
    case exportSessionFailed
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            String(localized: "error_no_audio_track")
        case .exportSessionFailed:
            String(localized: "error_export_session")
        case .exportFailed(let detail):
            String(format: String(localized: "error_extraction_failed"), detail)
        }
    }
}
