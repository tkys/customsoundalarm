import Foundation
@preconcurrency import AVFoundation
import os

/// サウンドプレビュー用の簡易プレイヤー
@Observable
@MainActor
final class AudioPlayer {
    static let shared = AudioPlayer()

    private let logger = Logger(subsystem: "com.tkysdev.customsoundalarm", category: "AudioPlayer")
    private var player: AVAudioPlayer?
    /// 夜中に急に大きな音が出ないよう、鳴り始めだけ短くフェードインする（#196）。
    private static let fadeInDuration: TimeInterval = 0.3

    private(set) var isPlaying = false
    private(set) var playingFileName: String?

    private init() {}

    /// 指定サウンドを再生（バンドルまたはLibrary/Sounds）
    /// - Parameter source: 鳴らした入口（計測用・#196）
    func play(_ sound: AlarmSound, source: SoundPreviewSource) {
        stop()

        let url: URL?
        if sound.isPreset {
            url = Bundle.main.url(
                forResource: sound.fileName.replacingOccurrences(of: ".caf", with: ""),
                withExtension: "caf"
            )
        } else {
            url = AudioConverter.shared.soundsDirectory.appendingPathComponent(sound.fileName)
        }

        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            logger.warning("Sound file not found: \(sound.fileName)")
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = 0
            player?.setVolume(0, fadeDuration: 0)
            player?.play()
            player?.setVolume(1, fadeDuration: Self.fadeInDuration)
            isPlaying = true
            playingFileName = sound.fileName

            AnalyticsService.shared.capture(.soundPreviewPlayed(source: source))

            // 5秒後に自動停止（プレビュー用）
            Task {
                try? await Task.sleep(for: .seconds(5))
                if playingFileName == sound.fileName {
                    stop()
                }
            }
        } catch {
            logger.error("Failed to play sound: \(error.localizedDescription)")
        }
    }

    /// 書き出したファイル（プレイリスト試聴）を最後まで再生する（#169）。
    /// 既存のサウンド試聴（5秒で停止）とは別に、停止ボタンで止める。
    func playFile(fileName: String) {
        stop()

        let importedURL = AudioConverter.shared.soundsDirectory
            .appendingPathComponent(fileName)
        let url: URL?
        if FileManager.default.fileExists(atPath: importedURL.path) {
            url = importedURL
        } else {
            let base = fileName.replacingOccurrences(of: ".caf", with: "")
            url = Bundle.main.url(forResource: base, withExtension: "caf")
        }

        guard let url else {
            logger.warning("Preview file not found: \(fileName)")
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = 0
            player?.play()
            isPlaying = true
            playingFileName = fileName

            let duration = player?.duration ?? 0
            Task {
                try? await Task.sleep(for: .seconds(duration + 0.2))
                if playingFileName == fileName {
                    stop()
                }
            }
        } catch {
            logger.error("Failed to play preview file: \(error.localizedDescription)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        playingFileName = nil
    }
}
