import Testing
import Foundation
import AVFoundation
@testable import CustomSoundAlarm

@MainActor
struct AudioConverterLoudnessTests {

    private func makeBuffer(
        amplitude: Float,
        duration: Double,
        silentRanges: [Range<Double>] = []
    ) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44_100,
            channels: 1,
            interleaved: false
        )!
        let frameCount = Int(44_100 * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let ptr = buffer.floatChannelData![0]

        var seed: UInt64 = 0x1234_5678_9ABC_DEF0
        for index in 0..<frameCount {
            let time = Double(index) / 44_100
            if silentRanges.contains(where: { $0.contains(time) }) {
                ptr[index] = 0
                continue
            }
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let random = Float(Int64(bitPattern: seed >> 33)) / Float(1 << 30)
            ptr[index] = amplitude * random
        }
        return buffer
    }

    private func writeCAF(_ buffer: AVAudioPCMBuffer) throws -> URL {
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
        try file.write(from: buffer)
        return url
    }

    private func sineBuffer(amplitude: Float, duration: Double) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44_100,
            channels: 1,
            interleaved: false
        )!
        let frameCount = Int(44_100 * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        for index in 0..<frameCount {
            buffer.floatChannelData![0][index] = Float(
                Double(amplitude) * sin(2 * Double.pi * 1000 * Double(index) / 44_100)
            )
        }
        return buffer
    }

    // MARK: - Pure gain logic

    @Test
    func normalizationGain_raisesToTarget() {
        let gain = AudioConverter.normalizationGain(
            measurement: .init(lufs: -24, peakDb: -20)
        )
        #expect(abs(gain - 10) < 0.001)
    }

    @Test
    func normalizationGain_capsByPeakHeadroom() {
        let gain = AudioConverter.normalizationGain(
            measurement: .init(lufs: -24, peakDb: -5)
        )
        #expect(abs(gain - 4) < 0.001)
    }

    @Test
    func normalizationGain_lowersLoudInput() {
        let gain = AudioConverter.normalizationGain(
            measurement: .init(lufs: -6, peakDb: -2)
        )
        #expect(abs(gain - (-8)) < 0.001)
    }

    @Test
    func normalizationGain_capsAtTwentyDb() {
        let gain = AudioConverter.normalizationGain(
            measurement: .init(lufs: -50, peakDb: -40)
        )
        #expect(abs(gain - 20) < 0.001)
    }

    @Test
    func normalizationGain_silentIsZero() {
        #expect(AudioConverter.normalizationGain(measurement: nil) == 0)
    }

    @Test
    func normalizationGain_peakAtCeilingCannotRaise() {
        #expect(AudioConverter.normalizationGain(
            measurement: .init(lufs: -20, peakDb: -1)
        ) == 0)
    }

    // MARK: - Conversion

    @Test
    func convert_smallNoise_becomesMinus14Lufs() async throws {
        let sourceURL = try writeCAF(makeBuffer(
            amplitude: 0.05,
            duration: 30,
            silentRanges: [0..<5, 10..<12, 20..<22]
        ))
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let input = try #require(LoudnessMeter.measure(fileURL: sourceURL))
        #expect(input.lufs < -20, "input should be small: \(input.lufs)")

        let result = try await AudioConverter.shared.convertToCAF(
            from: sourceURL,
            outputName: UUID().uuidString
        )
        defer { try? AudioConverter.shared.deleteSound(fileName: result.fileName) }

        let outputURL = AudioConverter.shared.soundsDirectory.appendingPathComponent(result.fileName)
        let output = try #require(LoudnessMeter.measure(fileURL: outputURL))

        #expect(abs(output.lufs - (-14)) <= 1, "output lufs was \(output.lufs)")
        #expect(output.peakDb <= -0.9, "output peak was \(output.peakDb)")
        #expect(result.gainDb > 0)
        #expect(abs((result.lufsBefore ?? 0) - input.lufs) < 0.2)
    }

    @Test
    func convert_loudSine_becomesMinus14Lufs() async throws {
        let sourceURL = try writeCAF(sineBuffer(amplitude: 0.7, duration: 30))
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let input = try #require(LoudnessMeter.measure(fileURL: sourceURL))
        #expect(input.lufs > -10, "input should be loud: \(input.lufs)")

        let result = try await AudioConverter.shared.convertToCAF(
            from: sourceURL,
            outputName: UUID().uuidString
        )
        defer { try? AudioConverter.shared.deleteSound(fileName: result.fileName) }

        let outputURL = AudioConverter.shared.soundsDirectory.appendingPathComponent(result.fileName)
        let output = try #require(LoudnessMeter.measure(fileURL: outputURL))

        #expect(abs(output.lufs - (-14)) <= 1, "output lufs was \(output.lufs)")
        #expect(output.peakDb <= -0.9, "output peak was \(output.peakDb)")
        #expect(result.gainDb < 0)
    }

    @Test
    func convert_silence_staysSilent() async throws {
        let sourceURL = try writeCAF(makeBuffer(amplitude: 0, duration: 5))
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let result = try await AudioConverter.shared.convertToCAF(
            from: sourceURL,
            outputName: UUID().uuidString
        )
        defer { try? AudioConverter.shared.deleteSound(fileName: result.fileName) }

        #expect(result.gainDb == 0)
        #expect(result.lufsBefore == nil)
        let outputURL = AudioConverter.shared.soundsDirectory.appendingPathComponent(result.fileName)
        #expect(LoudnessMeter.measure(fileURL: outputURL) == nil)
    }
}
