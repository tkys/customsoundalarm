import Testing
import Foundation
import AVFoundation
@testable import CustomSoundAlarm

@MainActor
struct AudioConverterPeakTests {

    private func makeSineFile(amplitude: Float, duration: Double = 1.0) throws -> URL {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)!
        let frameCount = AVAudioFrameCount(44100 * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AudioConverterError.bufferCreationFailed
        }
        buffer.frameLength = frameCount
        let ptr = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            let angle = 2.0 * Double.pi * 440.0 * Double(i) / 44100.0
            ptr[i] = amplitude * Float(sin(angle))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        } catch {
            print("makeSineFile write failed amplitude \(amplitude): \(error) \(String(describing: (error as NSError).userInfo))")
            throw error
        }
        return url
    }

    private func measurePeakDb(fileURL: URL) throws -> Double? {
        try AudioConverter.measurePeakDbSync(fileURL: fileURL)
    }

    @Test
    func testMakeSineFile() throws {
        let url = try makeSineFile(amplitude: 0.25)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(FileManager.default.fileExists(atPath: url.path))
        let file = try AVAudioFile(forReading: url)
        #expect(file.length > 0)
    }

    @Test
    func testMeasurePeakDirect() throws {
        let url = try makeSineFile(amplitude: 0.25)
        defer { try? FileManager.default.removeItem(at: url) }
        let peak = try AudioConverter.measurePeakDbSync(fileURL: url)
        #expect(peak != nil)
        if let peak {
            #expect(abs(peak - (-12.04)) < 0.5, "peak \(peak) should be -12")
        }
    }

    @Test
    func convert_sineMinus12dB_becomesMinus1dB() async throws {
        let sourceURL: URL
        do {
            sourceURL = try makeSineFile(amplitude: 0.25) // -12.04 dBFS
        } catch {
            Issue.record("makeSineFile -12dB failed: \(error)")
            throw error
        }
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let result: ConversionResult
        do {
            result = try await AudioConverter.shared.convertToCAF(from: sourceURL, outputName: UUID().uuidString)
        } catch {
            let ns = error as NSError
            Issue.record("convertToCAF -12dB failed: \(error) domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription) type=\(type(of: error))")
            throw error
        }
        defer { try? AudioConverter.shared.deleteSound(fileName: result.fileName) }

        let outputURL = AudioConverter.shared.soundsDirectory.appendingPathComponent(result.fileName)
        let peak = try measurePeakDb(fileURL: outputURL)
        #expect(peak != nil)
        if let peak {
            // Should be -1 dBFS ±0.2
            #expect(abs(peak - (-1.0)) < 0.2, "peak \(peak) should be -1 ±0.2")
        }
        // gain should be about 11 dB (from -12 to -1)
        #expect(abs(result.gainDb - 11.04) < 0.5)
    }

    @Test
    func convert_loudSine_unchanged() async throws {
        let sourceURL: URL
        do {
            sourceURL = try makeSineFile(amplitude: 1.0) // 0 dBFS
        } catch {
            Issue.record("makeSineFile loud failed: \(error) \(String(describing: error))")
            throw error
        }
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let result: ConversionResult
        do {
            result = try await AudioConverter.shared.convertToCAF(from: sourceURL, outputName: UUID().uuidString)
        } catch {
            let ns = error as NSError
            Issue.record("convertToCAF loud failed: \(error) domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription) type=\(type(of: error))")
            throw error
        }
        defer { try? AudioConverter.shared.deleteSound(fileName: result.fileName) }

        #expect(result.gainDb == 0)
        let outputURL = AudioConverter.shared.soundsDirectory.appendingPathComponent(result.fileName)
        let peak = try measurePeakDb(fileURL: outputURL)
        #expect(peak != nil)
        if let peak {
            #expect(abs(peak - 0.0) < 0.1, "loud input should stay near 0 dBFS, got \(peak)")
        }
    }

    @Test
    func convert_silence_staysSilent() async throws {
        let sourceURL: URL
        do {
            sourceURL = try makeSineFile(amplitude: 0.0)
        } catch {
            Issue.record("makeSineFile silent failed: \(error)")
            throw error
        }
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let result: ConversionResult
        do {
            result = try await AudioConverter.shared.convertToCAF(from: sourceURL, outputName: UUID().uuidString)
        } catch {
            let ns = error as NSError
            Issue.record("convertToCAF silent failed: \(error) domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription)")
            throw error
        }
        defer { try? AudioConverter.shared.deleteSound(fileName: result.fileName) }

        #expect(result.gainDb == 0)
        #expect(result.peakDb == nil)
        let outputURL = AudioConverter.shared.soundsDirectory.appendingPathComponent(result.fileName)
        let peak = try measurePeakDb(fileURL: outputURL)
        #expect(peak == nil)
    }
}
