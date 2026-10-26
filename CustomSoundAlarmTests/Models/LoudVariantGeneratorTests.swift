import Testing
import Foundation
import AVFoundation
@testable import CustomSoundAlarm

struct LoudVariantGeneratorTests {

    private func makeCAF(samples: [Float]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".caf")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100.0,
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

    private func crestDb(_ samples: [Float]) -> Double {
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        let meanSquare = samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count)
        let rms = sqrt(meanSquare)
        guard rms > 0 else { return 0 }
        return 20 * log10(Double(peak) / rms)
    }

    /// 打楽器風: 周期的（1.0秒ごと）な減衰 60ms のインパルス（0.3〜0.95）＋持続音
    private func percussive(seconds: Double = 30) -> [Float] {
        let count = Int(44_100 * seconds)
        var samples = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let time = Double(index) / 44_100
            var value = 0.145 * sin(2 * Double.pi * 220 * time)
            let beat = Int(floor(time / 1.0))
            let sinceBeat = time - Double(beat) * 1.0
            if sinceBeat < 0.06 {
                var seed = UInt64(beat) &* 6364136223846793005 &+ 1442695040888963407
                seed ^= seed >> 33
                let amplitude = 0.3 + 0.65 * (Double(seed % 1000) / 1000)
                value += amplitude * exp(-sinceBeat / 0.06)
                    * sin(2 * Double.pi * 1000 * sinceBeat)
            }
            samples[index] = Float(value)
        }
        return samples
    }

    /// とがった音: まれな全振幅スパイク＋小さい持続音
    private func spiky(seconds: Double = 30) -> [Float] {
        let count = Int(44_100 * seconds)
        var samples = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let time = Double(index) / 44_100
            var value = 0.02 * sin(2 * Double.pi * 220 * time)
            if index % 22_050 < 4 {
                value = 1.0
            }
            samples[index] = Float(value)
        }
        return samples
    }

    @Test
    func outputFileName_appendsLoud() {
        #expect(LoudVariantGenerator.outputFileName(for: "UUID.caf") == "UUID.loud.caf")
        #expect(LoudVariantGenerator.outputFileName(for: "PresetBeep.caf") == "PresetBeep.loud.caf")
    }

    @Test
    func signalsHaveRealisticCrestFactors() {
        #expect(crestDb(percussive()) >= 18, "percussive crest was \(crestDb(percussive()))")
        #expect(crestDb(spiky()) >= 28, "spiky crest was \(crestDb(spiky()))")
    }

    @Test
    func generate_sine_reachesMinus8Lufs() throws {
        let source = try makeCAF(samples: sine(amplitude: 0.28, seconds: 30))
        let output = outputURL()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: output)
        }

        let result = try LoudVariantGenerator.generate(
            sourceURL: source,
            outputURL: output,
            sourceFileName: "sine.caf",
            source: .imported
        )

        #expect(abs(result.outputLufs - (-8)) <= 1, "output lufs was \(result.outputLufs)")
        #expect(result.outputLufs >= result.sourceLufs + 6)
        #expect(result.outputLufs <= -7.5)
        let measurement = try #require(SoundLoudness.measure(fileURL: output))
        #expect(measurement.peakDb <= -0.95, "peak was \(measurement.peakDb)")
    }

    @Test
    func generate_percussive_meetsGapAndReductionLimit() throws {
        let samples = percussive()
        let source = try makeCAF(samples: samples)
        let output = outputURL()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: output)
        }

        let result = try LoudVariantGenerator.generate(
            sourceURL: source,
            outputURL: output,
            sourceFileName: "percussive.caf",
            source: .imported
        )

        #expect(result.outputLufs >= result.sourceLufs + 6,
                "source=\(result.sourceLufs) output=\(result.outputLufs)")
        #expect(result.outputLufs <= -7.5, "output lufs was \(result.outputLufs)")
        #expect(result.averageReductionDb <= 1.5,
                "average reduction was \(result.averageReductionDb) source=\(result.sourceLufs) output=\(result.outputLufs) gain=\(result.gainDb)")
        let measurement = try #require(SoundLoudness.measure(fileURL: output))
        #expect(measurement.peakDb <= -0.95, "peak was \(measurement.peakDb)")
    }

    @Test
    func generate_spiky_meetsGap() throws {
        let samples = spiky()
        let source = try makeCAF(samples: samples)
        let output = outputURL()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: output)
        }

        let result = try LoudVariantGenerator.generate(
            sourceURL: source,
            outputURL: output,
            sourceFileName: "spiky.caf",
            source: .imported
        )

        #expect(result.outputLufs >= result.sourceLufs + 6,
                "source=\(result.sourceLufs) output=\(result.outputLufs)")
        #expect(result.outputLufs <= -7.5, "output lufs was \(result.outputLufs)")
        let measurement = try #require(SoundLoudness.measure(fileURL: output))
        #expect(measurement.peakDb <= -0.95, "peak was \(measurement.peakDb)")
    }

    @Test
    func generate_90Seconds_isCappedTo60() throws {
        let source = try makeCAF(samples: sine(amplitude: 0.28, seconds: 90))
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
        let source = try makeCAF(samples: sine(amplitude: 0.28, seconds: 3))
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

    // MARK: - Candidate selection (#134)

    @Test
    func selectCandidate_keepsPlus6FloorForSpiky() {
        // 低減上限で止まるが、その手前は +6 に届かない → +6 に届く段を採る
        let candidates = [
            LoudVariantGenerator.GainCandidate(gain: 0, lufs: -18, averageReductionDb: 0),
            LoudVariantGenerator.GainCandidate(gain: 1.5, lufs: -16.5, averageReductionDb: 0.5),
            LoudVariantGenerator.GainCandidate(gain: 3, lufs: -15, averageReductionDb: 1.0),
            LoudVariantGenerator.GainCandidate(gain: 4.5, lufs: -13.5, averageReductionDb: 2.0),
            LoudVariantGenerator.GainCandidate(gain: 6, lufs: -12, averageReductionDb: 3.0)
        ]

        let selected = LoudVariantGenerator.selectCandidate(candidates, sourceLufs: -20)
        #expect(selected?.gain == 4.5)
        #expect((selected?.lufs ?? -999) >= -14)
    }

    @Test
    func selectCandidate_prefersBestWithinReductionWhenGapIsMet() {
        let candidates = [
            LoudVariantGenerator.GainCandidate(gain: 0, lufs: -18, averageReductionDb: 0),
            LoudVariantGenerator.GainCandidate(gain: 1.5, lufs: -14, averageReductionDb: 0.5),
            LoudVariantGenerator.GainCandidate(gain: 3, lufs: -12, averageReductionDb: 2.0)
        ]
        let selected = LoudVariantGenerator.selectCandidate(candidates, sourceLufs: -20)
        #expect(selected?.gain == 1.5)
    }

    @Test
    func selectCandidate_upperBoundWinsWhenGapIsAboveMinus8() {
        let candidates = [
            LoudVariantGenerator.GainCandidate(gain: 0, lufs: -12, averageReductionDb: 0),
            LoudVariantGenerator.GainCandidate(gain: 1.5, lufs: -10.5, averageReductionDb: 0),
            LoudVariantGenerator.GainCandidate(gain: 3, lufs: -9, averageReductionDb: 0),
            LoudVariantGenerator.GainCandidate(gain: 4.5, lufs: -7.5, averageReductionDb: 0)
        ]
        let selected = LoudVariantGenerator.selectCandidate(candidates, sourceLufs: -10)
        #expect(selected?.gain == 3)
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
}
