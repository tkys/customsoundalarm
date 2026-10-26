import Foundation
@preconcurrency import AVFoundation
import os

/// 変換結果（#106 / #134）。ラウドネス正規化の計測に使う
struct ConversionResult: Sendable {
    let fileName: String
    let peakDb: Double?
    let gainDb: Double
    /// 取り込み前の積分ラウドネス（LUFS）。無音なら nil
    let lufsBefore: Double?
}

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
    ) async throws -> ConversionResult {
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

        do {
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

        }

        // 変換結果を検証（outputFile はスコープを抜けて close 済み）
        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = attrs[.size] as? Int ?? 0
        guard fileSize > 0 else {
            throw AudioConverterError.conversionFailed(String(localized: "error_empty_file"))
        }

        // #134: BS.1770-4 の積分ラウドネスを測り、-14 LUFS にそろえる。
        // 上げる場合はピーク -1 dBFS を超えない範囲まで（リミッタは使わない）。
        let measurement = await Task.detached(priority: .userInitiated) {
            LoudnessMeter.measure(fileURL: outputURL)
        }.value
        let gainDb = Self.normalizationGain(measurement: measurement)
        if abs(gainDb) > 0.01 {
            try await Task.detached(priority: .userInitiated) {
                try Self.applyGainSync(fileURL: outputURL, gainDb: gainDb)
            }.value
        }

        logger.info("Converted audio to CAF: \(fileName) (\(fileSize) bytes) lufs=\(measurement?.lufs ?? -999) gain=\(gainDb)")
        return ConversionResult(
            fileName: fileName,
            peakDb: measurement?.peakDb,
            gainDb: gainDb,
            lufsBefore: measurement?.lufs
        )
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

    // MARK: - Loudness Normalization (#134)

    /// 取り込み後の目標ラウドネス
    nonisolated static let targetLufs: Double = -14
    /// ピークの上限
    nonisolated static let peakCeilingDb: Double = -1
    /// 上げる場合の上限
    nonisolated static let maxGainDb: Double = 20

    /// LUFS とピークから適用するゲインを決める（純ロジック・#134）。
    /// - 下げる場合はそのまま下げる
    /// - 上げる場合はピーク -1 dBFS を超えない範囲まで
    nonisolated static func normalizationGain(
        measurement: LoudnessMeter.Measurement?
    ) -> Double {
        guard let measurement else { return 0 }
        let desired = targetLufs - measurement.lufs
        if desired < 0 {
            return desired
        }
        let peakHeadroom = peakCeilingDb - measurement.peakDb
        guard peakHeadroom > 0 else { return 0 }
        return min(desired, peakHeadroom, maxGainDb)
    }

    // MARK: - Peak Normalization Helpers (#106, nonisolated for background execution)

    /// 変換後 CAF（PCM16 / mono）と同じ形式。読み書きの形式をそろえるため両方で使う
    nonisolated private static var pcm16Settings: [String: Any] {
        [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 44100.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false
        ]
    }

    /// ピーク dBFS を測る。無音なら nil。
    /// Int16 のまま読む（既定の Float32 で読むと、書き戻し側の Int16 と形式が合わない）。
    /// 末尾を越えて read するとエラーになるため framePosition で終端を判定する
    nonisolated static func measurePeakDbSync(fileURL: URL) throws -> Double? {
        let file = try AVAudioFile(forReading: fileURL, commonFormat: .pcmFormatInt16, interleaved: true)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096),
              let data = buffer.int16ChannelData else { return nil }
        let channels = Int(file.processingFormat.channelCount)
        var maxAbs: Int32 = 0
        while file.framePosition < file.length {
            try file.read(into: buffer)
            let count = Int(buffer.frameLength) * channels  // interleaved
            if count == 0 { break }
            for i in 0..<count {
                let v = Int32(data[0][i]).magnitude
                if v > maxAbs { maxAbs = Int32(v) }
            }
        }
        guard maxAbs > 0 else { return nil }
        return 20 * log10(Double(maxAbs) / 32768.0)
    }

    /// ゲインをかけて同じ形式で書き直す。クリップしないよう ±32767 に丸める
    nonisolated static func applyGainSync(fileURL: URL, gainDb: Double) throws {
        let linearGain = pow(10.0, gainDb / 20.0)
        let tempURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString + ".tmp.caf")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        do {
            let source = try AVAudioFile(forReading: fileURL, commonFormat: .pcmFormatInt16, interleaved: true)
            let dest = try AVAudioFile(
                forWriting: tempURL,
                settings: pcm16Settings,
                commonFormat: .pcmFormatInt16,
                interleaved: true
            )
            guard let buffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: 4096),
                  let data = buffer.int16ChannelData else {
                throw AudioConverterError.bufferCreationFailed
            }
            let channels = Int(source.processingFormat.channelCount)
            while source.framePosition < source.length {
                try source.read(into: buffer)
                let count = Int(buffer.frameLength) * channels
                if count == 0 { break }
                for i in 0..<count {
                    let amplified = (Double(data[0][i]) * linearGain).rounded()
                    data[0][i] = Int16(max(-32767, min(32767, amplified)))
                }
                try dest.write(from: buffer)
            }
        }  // dest をここで閉じてから置き換える
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
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
