import Foundation
@preconcurrency import AVFoundation
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

        guard let converter = AVAudioConverter(
            from: sourceFile.processingFormat,
            to: outputFile.processingFormat
        ) else {
            throw AudioConverterError.converterCreationFailed
        }

        let bufferSize: AVAudioFrameCount = 4096
        let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFile.processingFormat,
            frameCapacity: bufferSize
        )!

        // inputブロック内でソースファイルから読み込む（コンバーターが必要時に呼ぶ）
        var reachedEnd = false

        while !reachedEnd {
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFile.processingFormat,
                frameCapacity: bufferSize
            )!

            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                do {
                    try sourceFile.read(into: inputBuffer)
                    if inputBuffer.frameLength == 0 {
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                    outStatus.pointee = .haveData
                    return inputBuffer
                } catch {
                    outStatus.pointee = .endOfStream
                    return nil
                }
            }

            if let conversionError {
                throw AudioConverterError.conversionFailed(conversionError.localizedDescription)
            }

            switch status {
            case .haveData:
                if outputBuffer.frameLength > 0 {
                    try outputFile.write(from: outputBuffer)
                }
            case .endOfStream:
                if outputBuffer.frameLength > 0 {
                    try outputFile.write(from: outputBuffer)
                }
                reachedEnd = true
            case .error:
                throw AudioConverterError.conversionFailed(String(localized: "error_conversion_status"))
            case .inputRanDry:
                if outputBuffer.frameLength > 0 {
                    try outputFile.write(from: outputBuffer)
                }
            @unknown default:
                reachedEnd = true
            }
        }

        // 変換結果を検証
        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = attrs[.size] as? Int ?? 0
        guard fileSize > 0 else {
            throw AudioConverterError.conversionFailed(String(localized: "error_empty_file"))
        }

        logger.info("Converted audio to CAF: \(fileName) (\(fileSize) bytes)")
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
            String(localized: "error_buffer_creation")
        case .converterCreationFailed:
            String(localized: "error_converter_creation")
        case .conversionFailed(let detail):
            String(format: String(localized: "error_conversion_failed"), detail)
        }
    }
}
