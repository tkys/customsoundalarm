import Foundation
@preconcurrency import AVFoundation

/// ユーザーの音を「大きくした版」に変換する（#119）。
///
/// - 入力は先頭60秒まで
/// - ゲイン → Apple の Peak Limiter（`kAudioUnitSubType_PeakLimiter`）→ -1 dBFS にトリム
/// - 出力は既存と同じ PCM16 / 44.1kHz / mono CAF
/// - 元の音源は一切書き換えない
enum LoudVariantGenerator {

    /// 目標 RMS（LUFS の近似）
    static let targetRMSDb: Double = -9

    /// ゲイン上限
    static let maxGainDb: Double = 30

    /// オフライン描画の実測補正（モノラル→ミキサーで約3dB下がるため）
    static let engineCompensationDb: Double = 3

    /// 出力の最大長
    static let maxDuration: TimeInterval = 60

    /// 出力フォーマット
    static let sampleRate: Double = 44100

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
        source: Source
    ) throws -> Result {
        guard let sourceFile = try? AVAudioFile(forReading: sourceURL) else {
            throw GenerateError.unreadableSource
        }

        // 無音は失敗扱い（予備音にフォールバック）
        guard let measurement = SoundLoudness.measure(file: sourceFile) else {
            throw GenerateError.silentSource
        }

        let requestedGain = min(max(targetRMSDb - measurement.rmsDb, 0), maxGainDb)
        let gainDb = requestedGain + engineCompensationDb

        guard let buffer = loadMonoBuffer(file: sourceFile, maxSeconds: maxDuration) else {
            throw GenerateError.unreadableSource
        }

        try? FileManager.default.removeItem(at: outputURL)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
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

        let framesWritten = try renderWithPeakLimiter(
            buffer: buffer,
            gainDb: gainDb,
            outputFile: outputFile
        )

        let duration = Double(framesWritten) / sampleRate
        return Result(
            fileName: outputURL.lastPathComponent,
            gainDb: gainDb,
            durationSeconds: duration,
            source: source
        )
    }

    // MARK: - Load

    /// 先頭 maxSeconds までを 44.1kHz / mono / float32 で読む。
    static func loadMonoBuffer(file: AVAudioFile, maxSeconds: TimeInterval) -> AVAudioPCMBuffer? {
        let inputFormat = file.processingFormat
        let maxFrames = AVAudioFrameCount(
            min(Double(file.length), inputFormat.sampleRate * maxSeconds)
        )
        guard maxFrames > 0,
              let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: maxFrames)
        else { return nil }

        file.framePosition = 0
        do {
            try file.read(into: input, frameCount: maxFrames)
        } catch {
            return nil
        }
        guard input.frameLength > 0 else { return nil }

        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!

        // 44.1kHz mono ならそのまま
        if inputFormat.sampleRate == sampleRate,
           inputFormat.channelCount == 1,
           inputFormat.commonFormat == .pcmFormatFloat32 {
            return input
        }

        // まず mono に落とす（サンプルレートは維持）
        let monoSampleRate = inputFormat.sampleRate
        let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: monoSampleRate,
            channels: 1,
            interleaved: false
        )!
        guard let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: input.frameLength) else {
            return nil
        }
        mono.frameLength = input.frameLength
        let frames = Int(input.frameLength)
        let channels = Int(inputFormat.channelCount)
        if let source = input.floatChannelData {
            for index in 0..<frames {
                var sum: Float = 0
                for channel in 0..<channels {
                    sum += source[channel][index]
                }
                mono.floatChannelData![0][index] = sum / Float(channels)
            }
        } else if let source = input.int16ChannelData {
            for index in 0..<frames {
                var sum: Int32 = 0
                for channel in 0..<channels {
                    sum += Int32(source[channel][index])
                }
                mono.floatChannelData![0][index] = Float(sum) / Float(channels) / 32768.0
            }
        } else {
            return nil
        }

        if monoSampleRate == sampleRate {
            return mono
        }

        guard let converter = AVAudioConverter(from: monoFormat, to: outputFormat) else {
            return nil
        }
        let ratio = sampleRate / monoSampleRate
        let capacity = AVAudioFrameCount(Double(mono.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return nil
        }
        var error: NSError?
        var supplied = false
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .endOfStream
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return mono
        }
        guard error == nil, output.frameLength > 0 else { return nil }
        return output
    }

    // MARK: - Render

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
