import Foundation

enum SilentSoundLevel: String, Equatable, Sendable {
    case ok
    case veryQuiet = "very_quiet"
    case silent
}

enum SilentSoundAction: String, Equatable, Sendable {
    case reselect
    case otherSound = "other_sound"
    case useAnyway = "use_anyway"
}

/// 無音・ほぼ無音の判定（#256）。
enum SilentSoundLogic {
    /// 利得後の推定 LUFS がこれを下回ると「ほぼ無音」。
    static let veryQuietLufs: Double = -35

    /// 利得後のピークがこれ未満なら無音。
    static let silencePeakDb: Double = LoudnessNormalizer.silenceThresholdDb

    static func judge(
        lufsBefore: Double?,
        peakDb: Double?,
        gainDb: Double
    ) -> SilentSoundLevel {
        guard let peakDb else { return .silent }
        let peakAfter = peakDb + gainDb
        if peakAfter < silencePeakDb { return .silent }
        guard let lufsBefore else { return .ok }
        if lufsBefore + gainDb < veryQuietLufs { return .veryQuiet }
        return .ok
    }

    static func warningLevel(
        lufs: Double?,
        peakDb: Double?
    ) -> SilentSoundLevel {
        judge(lufsBefore: lufs, peakDb: peakDb, gainDb: 0)
    }
}
