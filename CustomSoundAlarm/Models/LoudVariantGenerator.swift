import Foundation
@preconcurrency import AVFoundation

/// ユーザーの音を「大きくした版」に変換する（#119 / #134）。
///
/// - 入力は先頭60秒まで
/// - ゲイン → Apple の Peak Limiter（`kAudioUnitSubType_PeakLimiter`）→ -1 dBFS にトリム
/// - 目標は −8 LUFS。描画後に LUFS を測り、1 LU 以上低ければゲインを足して描き直す（最大2回）
/// - 出力は既存と同じ PCM16 / 44.1kHz / mono CAF
/// - 元の音源は一切書き換えない
enum LoudVariantGenerator {

    /// 生成方式の版。古い版の `.loud.caf` は作り直す（#134）
    static let version: Int = 2

    /// 目標ラウドネス
    static let targetLufs: Double = -8

    /// ゲイン上限
    static let maxGainDb: Double = 30

    /// 出力の最大長
    static let maxDuration: TimeInterval = 60

    /// リミッタ後の最終トリム（-1 dBFS）
    static let outputTrimLinear: Float = 0.891

    enum Source: String, Sendable, Equatable {
        case imported
        case preset
    }

    enum GenerateError: String, Error, Equatable {
        case unreadableSource = "unreadable_source"
        case silentSource = "silent_source"
        case renderFailed = "render_failed"
        case writeFailed = "write_failed"
        case sourceMissing = "source_missing"
    }

    struct Result: Equatable, Sendable {
        let fileName: String
        let gainDb: Double
        let durationSeconds: Double
        let source: Source
        /// 元の音（先頭60秒）の LUFS
        let sourceLufs: Double
        /// 出力の LUFS（測り直し後）
        let outputLufs: Double
        /// 描画した回数（1 or 2）
        let attempts: Int
    }

    /// `<元の名前>.loud.caf`
    static func outputFileName(for sourceFileName: String) -> String {
        let base = sourceFileName.replacingOccurrences(of: ".caf", with: "")
        return "\(base).loud.caf"
    }

    static func generate(
        sourceURL: URL,
        outputURL: URL,
        sourceFileName: String,
        source: Source,
        firstPassGainOverride: Double? = nil
    ) throws -> Result {
        guard let buffer = AudioSampleLoader.loadMono44k(
            fileURL: sourceURL,
            maxSeconds: maxDuration
        ) else {
            throw GenerateError.unreadableSource
        }

        guard let sourceMeasurement = LoudnessMeter.measure(buffer: buffer) else {
            throw GenerateError.silentSource
        }

        let computedGain = min(max(targetLufs - sourceMeasurement.lufs, 0), maxGainDb)
        let initialGain = firstPassGainOverride ?? computedGain
        var gain = initialGain
        var attempts = 1

        var framesWritten = try renderPass(
            buffer: buffer,
            gainDb: gain,
            outputURL: outputURL
        )
        guard let firstOutput = LoudnessMeter.measure(fileURL: outputURL) else {
            throw GenerateError.renderFailed
        }
        var outputLufs = firstOutput.lufs

        // 2パス目: 1 LU 以上低ければゲインを足して描き直す（最大2回・上限30dB）
        if outputLufs < targetLufs - 1, gain < maxGainDb {
            gain = min(maxGainDb, gain + (targetLufs - outputLufs))
            attempts = 2
            framesWritten = try renderPass(
                buffer: buffer,
                gainDb: gain,
                outputURL: outputURL
            )
            guard let secondOutput = LoudnessMeter.measure(fileURL: outputURL) else {
                throw GenerateError.renderFailed
            }
            outputLufs = secondOutput.lufs
        }

        return Result(
            fileName: outputURL.lastPathComponent,
            gainDb: gain,
            durationSeconds: Double(framesWritten) / AudioSampleLoader.sampleRate,
            source: source,
            sourceLufs: sourceMeasurement.lufs,
            outputLufs: outputLufs,
            attempts: attempts
        )
    }

    // MARK: - Render

    private static func renderPass(
        buffer: AVAudioPCMBuffer,
        gainDb: Double,
        outputURL: URL
    ) throws -> AVAudioFrameCount {
        try? FileManager.default.removeItem(at: outputURL)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: AudioSampleLoader.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        guard let outputFile = try? AVAudioFile(
            forWriting: outputURL,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        ) else {
            throw GenerateError.writeFailed
        }
        return try renderWithPeakLimiter(
            buffer: buffer,
            gainDb: gainDb,
            outputFile: outputFile
        )
    }

    /// ゲイン → Peak Limiter → -1 dBFS トリムでオフライン描画し、CAF に書き出す。
    /// - Returns: 書き出したフレーム数
    static func renderWithPeakLimiter(
        buffer: AVAudioPCMBuffer,
        gainDb: Double,
        outputFile: AVAudioFile,
        useLimiter: Bool = true
    ) throws -> AVAudioFrameCount {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let eq = AVAudioUnitEQ(numberOfBands: 0)
        eq.globalGain = Float(gainDb)
        let limiter = AVAudioUnitEffect(audioComponentDescription: Self.peakLimiterDescription)

        engine.attach(player)
        engine.attach(eq)
        if useLimiter {
            engine.attach(limiter)
        }

        let format = buffer.format
        engine.connect(player, to: eq, format: format)
        if useLimiter {
            engine.connect(eq, to: limiter, format: format)
            engine.connect(limiter, to: engine.mainMixerNode, format: format)
        } else {
            engine.connect(eq, to: engine.mainMixerNode, format: format)
        }
        engine.mainMixerNode.outputVolume = Self.outputTrimLinear

        do {
            try engine.enableManualRenderingMode(
                .offline,
                format: format,
                maximumFrameCount: 4096
            )
            try engine.start()
        } catch {
            throw GenerateError.renderFailed
        }
        defer { engine.stop() }

        guard let renderBuffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: 4096
        ) else {
            throw GenerateError.renderFailed
        }

        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()

        var remaining = buffer.frameLength
        var written: AVAudioFrameCount = 0
        var guardCount = 0
        while remaining > 0 {
            guardCount += 1
            if guardCount > 100_000 { throw GenerateError.renderFailed }
            let frames = min(4096, remaining)
            let status: AVAudioEngineManualRenderingStatus
            do {
                status = try engine.renderOffline(frames, to: renderBuffer)
            } catch {
                throw GenerateError.renderFailed
            }
            switch status {
            case .success:
                guard renderBuffer.frameLength > 0 else { throw GenerateError.renderFailed }
                do {
                    try outputFile.write(from: renderBuffer)
                } catch {
                    throw GenerateError.writeFailed
                }
                written += renderBuffer.frameLength
                remaining -= min(remaining, renderBuffer.frameLength)
            case .cannotDoInCurrentContext:
                continue
            case .insufficientDataFromInputNode, .error:
                throw GenerateError.renderFailed
            @unknown default:
                throw GenerateError.renderFailed
            }
        }
        return written
    }

    private static var peakLimiterDescription: AudioComponentDescription {
        AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
    }
}
