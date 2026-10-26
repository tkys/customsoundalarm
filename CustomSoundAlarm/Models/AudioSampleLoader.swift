import Foundation
@preconcurrency import AVFoundation

/// 音声ファイルを 44.1kHz / mono / float32 で読み込む（#134）。
enum AudioSampleLoader {
    static let sampleRate: Double = 44_100

    static func loadMono44k(fileURL: URL, maxSeconds: TimeInterval? = nil) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: fileURL) else { return nil }
        return loadMono44k(file: file, maxSeconds: maxSeconds)
    }

    static func loadMono44k(file: AVAudioFile, maxSeconds: TimeInterval? = nil) -> AVAudioPCMBuffer? {
        let inputFormat = file.processingFormat
        let maxFrames: AVAudioFrameCount
        if let maxSeconds {
            maxFrames = AVAudioFrameCount(
                min(Double(file.length), inputFormat.sampleRate * maxSeconds)
            )
        } else {
            maxFrames = AVAudioFrameCount(min(Double(file.length), Double(AVAudioFrameCount.max)))
        }
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
}
