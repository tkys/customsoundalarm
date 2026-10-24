import Testing
import Foundation
import AVFoundation
@testable import CustomSoundAlarm

struct SoundLoudnessTests {

    // MARK: - Helpers

    private func backupURL() -> URL? {
        Bundle.main.url(forResource: "PresetBackupLoud", withExtension: "caf")
    }

    private func makeTempCAF(samples: [Float], sampleRate: Double = 44100) throws -> URL {
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

    // MARK: - Backup sound (#109 B)

    @Test
    func backupSound_existsInBundle() {
        #expect(backupURL() != nil, "PresetBackupLoud.caf must be bundled")
    }

    @Test
    func backupSound_formatAndDuration() throws {
        let url = try #require(backupURL())
        let file = try AVAudioFile(forReading: url)

        #expect(file.fileFormat.sampleRate == 44100)
        #expect(file.fileFormat.channelCount == 1)
        #expect(file.fileFormat.commonFormat == .pcmFormatInt16)
        let seconds = Double(file.length) / file.fileFormat.sampleRate
        #expect(seconds >= 20 && seconds <= 30, "duration was \(seconds)s")
    }

    @Test
    func backupSound_peakAndLoudness() throws {
        let url = try #require(backupURL())
        let measurement = try #require(SoundLoudness.measure(fileURL: url))

        // ピーク −1 dBFS、RMS（無音除外）は −10〜−6 dBFS。
        // LUFS の代用判定として RMS を使う（#109 のテスト仕様）。
        #expect(abs(measurement.peakDb - (-1.0)) <= 0.5, "peak was \(measurement.peakDb)")
        #expect(measurement.rmsDb >= -10 && measurement.rmsDb <= -6, "rms was \(measurement.rmsDb)")
    }

    @Test
    @MainActor
    func backupSound_isLoudestAmongPresets() throws {
        let url = try #require(backupURL())
        let backup = try #require(SoundLoudness.measure(fileURL: url))

        for preset in SoundStore.presetDefinitions {
            let name = preset.fileName.replacingOccurrences(of: ".caf", with: "")
            guard let url = Bundle.main.url(forResource: name, withExtension: "caf"),
                  let measurement = SoundLoudness.measure(fileURL: url) else {
                continue
            }
            #expect(backup.rmsDb > measurement.rmsDb, "\(preset.fileName) was louder than backup")
        }
    }

    // MARK: - Measurement

    @Test
    func measure_excludesSilentWindows() throws {
        // 0.5秒無音 + 1秒 -12 dBFS + 0.5秒無音
        let silence = [Float](repeating: 0, count: 22050)
        let tone = (0..<44100).map { index in
            Float(0.25 * sin(2 * Double.pi * 440 * Double(index) / 44100))
        }
        let url = try makeTempCAF(samples: silence + tone + silence)
        defer { try? FileManager.default.removeItem(at: url) }

        let measurement = try #require(SoundLoudness.measure(fileURL: url))

        // 振幅 0.25 の正弦波: ピーク −12.04 dBFS、RMS はその 3.01 dB 下
        #expect(abs(measurement.rmsDb - (-15.05)) < 0.3, "rms was \(measurement.rmsDb)")
        #expect(abs(measurement.peakDb - (-12.04)) < 0.3, "peak was \(measurement.peakDb)")
    }

    @Test
    func measure_returnsNilForSilence() throws {
        let url = try makeTempCAF(samples: [Float](repeating: 0, count: 44100))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(SoundLoudness.measure(fileURL: url) == nil)
    }
}
