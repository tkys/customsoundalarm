import Testing
import Foundation
import AVFoundation
@testable import CustomSoundAlarm

struct LoudnessMeterTests {

    private func buffer(amplitude: Float, seconds: Double, frequency: Double = 1000) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44_100,
            channels: 1,
            interleaved: false
        )!
        let count = Int(44_100 * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
        buffer.frameLength = AVAudioFrameCount(count)
        for index in 0..<count {
            buffer.floatChannelData![0][index] = Float(
                Double(amplitude) * sin(2 * Double.pi * frequency * Double(index) / 44_100)
            )
        }
        return buffer
    }

    @Test
    func sineFullScale_isMinusThreeLufs() throws {
        let measurement = try #require(LoudnessMeter.measure(buffer: buffer(amplitude: 1.0, seconds: 3)))
        #expect(abs(measurement.lufs - (-3.0)) <= 0.2, "lufs was \(measurement.lufs)")
    }

    @Test
    func sineTenth_isMinusTwentyThreeLufs() throws {
        let measurement = try #require(LoudnessMeter.measure(buffer: buffer(amplitude: 0.1, seconds: 3)))
        #expect(abs(measurement.lufs - (-23.0)) <= 0.2, "lufs was \(measurement.lufs)")
    }

    @Test
    func silence_returnsNil() {
        #expect(LoudnessMeter.measure(buffer: buffer(amplitude: 0, seconds: 3)) == nil)
    }

    @Test
    func gating_ignoresLeadingSilence() throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44_100,
            channels: 1,
            interleaved: false
        )!
        let silence = Int(44_100 * 2)
        let tone = Int(44_100 * 3)
        let count = silence + tone
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
        buffer.frameLength = AVAudioFrameCount(count)
        for index in 0..<silence {
            buffer.floatChannelData![0][index] = 0
        }
        for index in 0..<tone {
            buffer.floatChannelData![0][silence + index] = Float(
                0.1 * sin(2 * Double.pi * 1000 * Double(index) / 44_100)
            )
        }

        let measurement = try #require(LoudnessMeter.measure(buffer: buffer))
        #expect(abs(measurement.lufs - (-23.0)) <= 0.5, "lufs was \(measurement.lufs)")
    }

    @Test
    func buckets() {
        #expect(LoudnessMeter.bucket(forLufs: nil) == "silent")
        #expect(LoudnessMeter.bucket(forLufs: -8) == ">=-9")
        #expect(LoudnessMeter.bucket(forLufs: -12) == "-9~-14")
        #expect(LoudnessMeter.bucket(forLufs: -16) == "-14~-20")
        #expect(LoudnessMeter.bucket(forLufs: -25) == "-20~-30")
        #expect(LoudnessMeter.bucket(forLufs: -35) == "<-30")
    }
}
