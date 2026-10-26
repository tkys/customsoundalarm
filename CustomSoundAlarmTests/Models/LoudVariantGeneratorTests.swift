import Testing
import Foundation
import AVFoundation
@testable import CustomSoundAlarm

struct LoudVariantGeneratorTests {

    private func makeCAF(samples: [Float], sampleRate: Double = 44_100) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".caf")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let format = file.processingFormat
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        )!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for index in samples.indices {
            buffer.floatChannelData![0][index] = samples[index]
        }
        try file.write(from: buffer)
        return url
    }

    private func outputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".loud.caf")
    }

    private func sine(amplitude: Float, seconds: Double, frequency: Double = 1000) -> [Float] {
        let count = Int(44_100 * seconds)
        return (0..<count).map { index in
            Float(Double(amplitude) * sin(2 * Double.pi * frequency * Double(index) / 44_100))
        }
    }

    @Test
    func outputFileName_appendsLoud() {
        #expect(LoudVariantGenerator.outputFileName(for: "UUID.caf") == "UUID.loud.caf")
        #expect(LoudVariantGenerator.outputFileName(for: "PresetBeep.caf") == "PresetBeep.loud.caf")
    }

    @Test
    func generate_reachesMinus8LufsAndPlus6OverSource() throws {
        // 元の音: 約 -15 LUFS（取り込み後 -14 に近い想定）
        let source = try makeCAF(samples: sine(amplitude: 0.28, seconds: 30))
        let output = outputURL()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: output)
        }

        let result = try LoudVariantGenerator.generate(
            sourceURL: source,
            outputURL: output,
            sourceFileName: "source.caf",
            source: .imported
        )

        #expect(abs(result.outputLufs - (-8)) <= 1, "output lufs was \(result.outputLufs)")
        #expect(
            result.outputLufs >= result.sourceLufs + 6,
            "expected +6 over source: source=\(result.sourceLufs) output=\(result.outputLufs)"
        )
        #expect(result.attempts >= 1)
        #expect(result.attempts <= 2)

        let measured = try #require(LoudnessMeter.measure(fileURL: output))
        #expect(abs(measured.lufs - result.outputLufs) < 0.2)
    }

    @Test
    func generate_highCrestInput_keepsPeakBelowMinus1() throws {
        var samples = sine(amplitude: 0.02, seconds: 5)
        for index in stride(from: 0, to: samples.count, by: 22_050) {
            for offset in 0..<4 where index + offset < samples.count {
                samples[index + offset] = 1.0
            }
        }
        let source = try makeCAF(samples: samples)
        let output = outputURL()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: output)
        }

        _ = try LoudVariantGenerator.generate(
            sourceURL: source,
            outputURL: output,
            sourceFileName: "spiky.caf",
            source: .imported
        )

        let measurement = try #require(SoundLoudness.measure(fileURL: output))
        #expect(measurement.peakDb <= -0.9, "peak was \(measurement.peakDb)")
    }

    @Test
    func generate_alreadyLoudInput_keepsPeakBelowMinus1() throws {
        let source = try makeCAF(samples: sine(amplitude: 0.9, seconds: 5))
        let output = outputURL()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: output)
        }

        _ = try LoudVariantGenerator.generate(
            sourceURL: source,
            outputURL: output,
            sourceFileName: "loud.caf",
            source: .preset
        )

        let measurement = try #require(SoundLoudness.measure(fileURL: output))
        #expect(measurement.peakDb <= -0.9, "peak was \(measurement.peakDb)")
    }

    @Test
    func generate_90Seconds_isCappedTo60() throws {
        let source = try makeCAF(samples: sine(amplitude: 0.4, seconds: 90))
        let output = outputURL()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: output)
        }

        let result = try LoudVariantGenerator.generate(
            sourceURL: source,
            outputURL: output,
            sourceFileName: "long.caf",
            source: .imported
        )

        #expect(result.durationSeconds <= 60.1)
        #expect(result.durationSeconds >= 59.5)
    }

    @Test
    func generate_silentInput_fails() throws {
        let source = try makeCAF(samples: [Float](repeating: 0, count: 44_100))
        let output = outputURL()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: output)
        }

        #expect(throws: LoudVariantGenerator.GenerateError.silentSource) {
            try LoudVariantGenerator.generate(
                sourceURL: source,
                outputURL: output,
                sourceFileName: "silent.caf",
                source: .imported
            )
        }
    }

    @Test
    func generate_doesNotModifySource() throws {
        let source = try makeCAF(samples: sine(amplitude: 0.4, seconds: 3))
        let output = outputURL()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: output)
        }
        let before = try Data(contentsOf: source)

        _ = try LoudVariantGenerator.generate(
            sourceURL: source,
            outputURL: output,
            sourceFileName: "source.caf",
            source: .imported
        )

        #expect(try Data(contentsOf: source) == before)
    }

    @Test
    func analyticsBuckets() {
        #expect(LoudVariantGenerator.gainDbBucket(0) == "0")
        #expect(LoudVariantGenerator.gainDbBucket(3) == "0~6")
        #expect(LoudVariantGenerator.gainDbBucket(9) == "6~12")
        #expect(LoudVariantGenerator.gainDbBucket(15) == "12~20")
        #expect(LoudVariantGenerator.gainDbBucket(25) == "20~30")
        #expect(LoudVariantGenerator.durationBucket(10) == "under_30s")
        #expect(LoudVariantGenerator.durationBucket(45) == "30_60s")
        #expect(LoudVariantGenerator.durationBucket(60) == "60s")
    }

    /// 2パス目の検証: 1パス目が意図的に低い場合でも、測り直して目標に届く（#134）
    @Test
    func generate_secondPassCorrectsLowFirstPass() throws {
        let source = try makeCAF(samples: sine(amplitude: 0.28, seconds: 30))
        let output = outputURL()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: output)
        }

        let sourceLufs = try #require(LoudnessMeter.measure(fileURL: source)).lufs
        let fullGain = min(max(LoudVariantGenerator.targetLufs - sourceLufs, 0), LoudVariantGenerator.maxGainDb)

        let result = try LoudVariantGenerator.generate(
            sourceURL: source,
            outputURL: output,
            sourceFileName: "retry.caf",
            source: .imported,
            firstPassGainOverride: fullGain - 4
        )

        #expect(result.attempts == 2)
        #expect(abs(result.outputLufs - (-8)) <= 1, "output lufs was \(result.outputLufs)")
        #expect(result.outputLufs >= result.sourceLufs + 6, "source=\(result.sourceLufs) output=\(result.outputLufs)")
    }
}
