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

    private(set) var isPlaying = false
    private(set) var playingFileName: String?

    private init() {}

    /// 指定サウンドを再生（バンドルまたはLibrary/Sounds）
    func play(_ sound: AlarmSound) {
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
            player?.play()
            isPlaying = true
            playingFileName = sound.fileName

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

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        playingFileName = nil
    }
}
