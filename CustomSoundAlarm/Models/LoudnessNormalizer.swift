import Foundation

/// 取り込み音源のピークノーマライズ（#106）。
/// - 対象: AudioConverter.convertToCAF の出力（PCM 16-bit / 44.1kHz / mono CAF）
/// - 処理: ピークを -1 dBFS にそろえる。上げるだけで下げない、上限 +20 dB、-60 dBFS 未満は無音扱い
enum LoudnessNormalizer {

    /// 目標ピーク
    static let targetPeakDb: Double = -1.0

    /// ゲイン上限（ほぼ無音のノイズを持ち上げないため）
    static let maxGainDb: Double = 20.0

    /// 無音とみなすしきい値（これ未満は処理しない）
    static let silenceThresholdDb: Double = -60.0

    /// ピーク dBFS から適用すべきゲイン dB を返す。
    /// - Parameter peakDb: 処理前のピーク dBFS（nil = 無音/計測不可）
    /// - Returns: 適用するゲイン dB（0...20、上げるだけ）
    static func gainDb(forPeakDb peakDb: Double?) -> Double {
        guard let peakDb, peakDb >= silenceThresholdDb else { return 0 }
        let rawGain = targetPeakDb - peakDb
        if rawGain <= 0 { return 0 }
        return min(rawGain, maxGainDb)
    }

    /// 処理前のピーク dBFS をバケットに分類（計測用）。
    /// 生の値は送らず区分で送る。
    /// - Returns: ">=-1" / "-1~-3" / "-3~-6" / "-6~-12" / "<-12" / "silent"
    static func peakDbBucket(forPeakDb peakDb: Double?) -> String {
        guard let peakDb, peakDb >= silenceThresholdDb else { return "silent" }
        if peakDb >= -1 { return ">=-1" }
        if peakDb > -3 { return "-1~-3" }
        if peakDb > -6 { return "-3~-6" }
        if peakDb >= -12 { return "-6~-12" }
        return "<-12"
    }

    /// かけたゲイン dB をバケットに分類（計測用）。
    /// - Returns: "0" / "0~3" / "3~6" / "6~12" / "12~20"
    static func gainDbBucket(forGainDb gainDb: Double) -> String {
        if gainDb <= 0 { return "0" }
        if gainDb <= 3 { return "0~3" }
        if gainDb <= 6 { return "3~6" }
        if gainDb <= 12 { return "6~12" }
        return "12~20"
    }
}
