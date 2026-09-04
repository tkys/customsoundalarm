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
    ///   - startTime: 切り出し開始時間（秒）。nil で先頭から
    ///   - endTime: 切り出し終了時間（秒）。nil で末尾まで
    /// - Returns: 変換後のCAFファイル名
    ///
    /// #77: 波形クロップUIからの範囲指定変換に対応。
    /// ソースの `framePosition` を開始位置に_seek_し、目的フレーム数に達したら入力を打ち切る。
    func convertToCAF(
        from sourceURL: URL,
        outputName: String,
        startTime: Double? = nil,
        endTime: Double? = nil
    ) async throws -> String {
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

        // #77: 範囲指定があるときは読み取り位置と打ち切りフレームを決める
        let sourceSampleRate = sourceFile.processingFormat.sampleRate
        let totalFrames = sourceFile.length
        let rangeStartFrame: AVAudioFramePosition
        let rangeEndFrame: AVAudioFramePosition
        if let startTime, startTime > 0 {
            rangeStartFrame = min(max(Int64(startTime * sourceSampleRate), 0), totalFrames)
        } else {
            rangeStartFrame = 0
        }
        if let endTime, endTime > startTime ?? 0 {
            rangeEndFrame = min(max(Int64(endTime * sourceSampleRate), rangeStartFrame), totalFrames)
        } else {
            rangeEndFrame = totalFrames
        }
        guard rangeEndFrame > rangeStartFrame else {
            throw AudioConverterError.conversionFailed(String(localized: "error_empty_file"))
        }
        sourceFile.framePosition = rangeStartFrame

        let bufferSize: AVAudioFrameCount = 4096
        let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFile.processingFormat,
            frameCapacity: bufferSize
        )!

        // inputブロック内でソースファイルから読み込む（コンバーターが必要時に呼ぶ）
        // #77: 目的フレーム数に達したら endOfStream を返して打ち切る
        var remainingFrames = rangeEndFrame - rangeStartFrame

        while remainingFrames > 0 {
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
                    // 範囲末尾を超えて読んだ分は切り捨てる
                    if AVAudioFramePosition(inputBuffer.frameLength) > remainingFrames {
                        inputBuffer.frameLength = AVAudioFrameCount(remainingFrames)
                    }
                    remainingFrames -= AVAudioFramePosition(inputBuffer.frameLength)
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
                remainingFrames = 0
            case .error:
                throw AudioConverterError.conversionFailed(String(localized: "error_conversion_status"))
            case .inputRanDry:
                if outputBuffer.frameLength > 0 {
                    try outputFile.write(from: outputBuffer)
                }
                if remainingFrames > 0, sourceFile.framePosition >= rangeEndFrame {
                    remainingFrames = 0
                }
            @unknown default:
                remainingFrames = 0
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

    /// CAF ファイルの秒数を取得する（追加時に記録する目的・#68）。
    /// 計測失敗（ファイル欠損・無効なアセット等）は nil を返す。
    /// 起動のたびに全ファイルを読まないよう、追加時計測と欠損分の一度きり補完のみで使う。
    func measureDurationSeconds(fileName: String) -> Double? {
        let url = soundsDirectory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        guard seconds.isFinite, seconds > 0 else { return nil }
        return seconds
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
