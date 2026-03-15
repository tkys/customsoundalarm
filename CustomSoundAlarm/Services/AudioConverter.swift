import Foundation
import AVFoundation
import os

/// 音声ファイルをAlarmKit互換のCAF形式に変換し、Library/Soundsに配置する
@MainActor
final class AudioConverter {
    static let shared = AudioConverter()

    private let logger = Logger(subsystem: "com.tkysdev.customsoundalarm", category: "AudioConverter")

    /// Library/Sounds ディレクトリ（AlarmKitが.named()で参照するパス）
    var soundsDirectory: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let sounds = library.appendingPathComponent("Sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: sounds, withIntermediateDirectories: true)
        return sounds
    }

    private init() {}

    /// 指定URLの音声ファイルをCAFに変換してLibrary/Soundsに保存
    /// - Parameters:
    ///   - sourceURL: 元の音声ファイル（MP3, AAC, WAV, M4A等）
    ///   - outputName: 出力ファイル名（拡張子なし）
    /// - Returns: 変換後のCAFファイル名
    func convertToCAF(from sourceURL: URL, outputName: String) async throws -> String {
        let fileName = "\(outputName).caf"
        let outputURL = soundsDirectory.appendingPathComponent(fileName)

        // 既に存在する場合は上書き
        try? FileManager.default.removeItem(at: outputURL)

        let sourceFile = try AVAudioFile(forReading: sourceURL)

        // CAF形式: PCM 16-bit, 44.1kHz, mono
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: outputSettings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )

        // バッファを使って変換コピー
        let bufferSize: AVAudioFrameCount = 4096
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: sourceFile.processingFormat,
            frameCapacity: bufferSize
        ) else {
            throw AudioConverterError.bufferCreationFailed
        }

        // フォーマット変換用のコンバーター
        guard let converter = AVAudioConverter(
            from: sourceFile.processingFormat,
            to: outputFile.processingFormat
        ) else {
            throw AudioConverterError.converterCreationFailed
        }

        let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFile.processingFormat,
            frameCapacity: bufferSize
        )!

        while true {
            do {
                try sourceFile.read(into: buffer)
            } catch {
                break
            }

            if buffer.frameLength == 0 { break }

            var error: NSError?
            converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if let error {
                throw AudioConverterError.conversionFailed(error.localizedDescription)
            }

            try outputFile.write(from: outputBuffer)
        }

        logger.info("Converted audio to CAF: \(fileName)")
        return fileName
    }

    /// Library/Soundsにあるサウンドファイル一覧
    func listSavedSounds() -> [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: soundsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents
            .filter { $0.pathExtension == "caf" }
            .map { $0.lastPathComponent }
    }

    /// サウンドファイルを削除
    func deleteSound(fileName: String) throws {
        let url = soundsDirectory.appendingPathComponent(fileName)
        try FileManager.default.removeItem(at: url)
        logger.info("Deleted sound: \(fileName)")
    }
}

enum AudioConverterError: LocalizedError {
    case bufferCreationFailed
    case converterCreationFailed
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .bufferCreationFailed:
            "音声バッファの作成に失敗しました"
        case .converterCreationFailed:
            "音声コンバーターの作成に失敗しました"
        case .conversionFailed(let detail):
            "音声変換に失敗しました: \(detail)"
        }
    }
}
