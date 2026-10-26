import Foundation

/// 変換後 CAF のサイズ見積り（#79-8）。
///
/// AudioConverter の出力は PCM 16bit / 44.1kHz / モノラルで **88,200 bytes/秒**。
/// 音声の尺は無制限の方針（v1.5.0）のため、生成前にサイズを見せることで
/// 1時間 ≈ 317MB のような巨大ファイルを無警告で作らせない。
/// 目安: 10分 ≈ 53MB、30分 ≈ 159MB。
enum AudioSizeEstimate {

    /// PCM 16bit / 44.1kHz / モノラル の秒あたりバイト数
    static let bytesPerSecond: Double = 44_100 * 2

    /// サイズ注意を出すしきい値（バイト）。20MB（#123）
    static let sizeWarningThresholdBytes: Double = 20_000_000

    /// 変換後のおおよそのファイルサイズ（バイト）
    static func estimatedFileSize(seconds: Double) -> Double {
        max(0, seconds) * bytesPerSecond
    }

    /// バイト数 → "52.9 MB" 形式。
    /// 100MB 未満は小数1位、以上は整数（10分=52.9MB、30分=159MB の目安に合わせる）
    static func formattedSize(bytes: Double) -> String {
        let mb = max(0, bytes) / 1_000_000
        if mb >= 100 {
            return String(format: "%.0f MB", mb)
        }
        return String(format: "%.1f MB", mb)
    }

    /// 20MB 以上のときだけ容量の注意を表示する（#123）。
    static func shouldShowWarning(bytes: Double) -> Bool {
        bytes >= sizeWarningThresholdBytes
    }

    static func shouldShowWarning(seconds: Double) -> Bool {
        shouldShowWarning(bytes: estimatedFileSize(seconds: seconds))
    }
}