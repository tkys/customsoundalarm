import Foundation

/// プレイリストの並び・長さ・フェードの純ロジック（#151）。
/// 実ファイルの読み書きは `PlaylistRenderer` が行う。
enum PlaylistRenderLogic {
    static let sampleRate: Double = 44_100

    // MARK: - Order

    /// モードに応じた曲順を返す。
    /// - `.playlistShuffle` は固定シードで再現可能
    /// - `.playlistRandom` は候補から1曲
    static func orderedTracks(
        _ tracks: [PlaylistTrack],
        mode: PlaylistSoundMode,
        seed: UInt64
    ) -> [PlaylistTrack] {
        switch mode {
        case .single, .playlistOrder:
            return tracks
        case .playlistShuffle:
            guard tracks.count > 1 else { return tracks }
            var generator = SplitMix64(seed: seed)
            return tracks.shuffled(using: &generator)
        case .playlistRandom:
            guard !tracks.isEmpty else { return [] }
            let index = Int(seed % UInt64(tracks.count))
            return [tracks[index]]
        }
    }

    // MARK: - Duration / 10 min limit

    /// クロスフェードで重なる長さの合計。
    /// 曲がフェード秒より短い場合は、短い方の曲の長さまでしか重ねない。
    static func crossfadeOverlap(
        trackDurations: [TimeInterval],
        seconds: TimeInterval
    ) -> TimeInterval {
        guard trackDurations.count > 1, seconds > 0 else { return 0 }
        return (0..<(trackDurations.count - 1)).reduce(0) { total, index in
            let left = max(0, trackDurations[index])
            let right = max(0, trackDurations[index + 1])
            return total + min(seconds, min(left, right))
        }
    }

    /// 書き出し後の合計時間。クロスフェードの重なり分を差し引く。
    static func totalDuration(
        trackDurations: [TimeInterval],
        fade: PlaylistFadeSettings
    ) -> TimeInterval {
        let sum = trackDurations.reduce(0) { $0 + max(0, $1) }
        guard fade.gapFade == .crossfade else { return sum }
        return max(0, sum - crossfadeOverlap(
            trackDurations: trackDurations,
            seconds: PlaylistGapFade.crossfade.seconds
        ))
    }

    /// 10分以内か（浮動小数の誤差を許容）
    static func isWithinLimit(
        trackDurations: [TimeInterval],
        fade: PlaylistFadeSettings
    ) -> Bool {
        totalDuration(trackDurations: trackDurations, fade: fade)
            <= Playlist.maxTotalSeconds + 0.001
    }

    // MARK: - Fade curves

    /// 先頭から `fadeSeconds` の間で 0 → 1 に上がる係数。
    /// `index` は先頭からのフレーム番号。
    static func fadeInGain(
        index: Int,
        fadeSeconds: TimeInterval,
        sampleRate: Double = sampleRate
    ) -> Float {
        guard fadeSeconds > 0, index >= 0 else { return 1 }
        let fadeFrames = Int((fadeSeconds * sampleRate).rounded())
        guard fadeFrames > 0 else { return 1 }
        if index >= fadeFrames { return 1 }
        return Float(index) / Float(fadeFrames)
    }

    /// 末尾から `fadeSeconds` の間で 1 → 0 に下がる係数。
    /// `indexFromEnd` は最後のフレームを 0 とする。
    static func fadeOutGain(
        indexFromEnd: Int,
        fadeSeconds: TimeInterval,
        sampleRate: Double = sampleRate
    ) -> Float {
        guard fadeSeconds > 0, indexFromEnd >= 0 else { return 1 }
        let fadeFrames = Int((fadeSeconds * sampleRate).rounded())
        guard fadeFrames > 0 else { return 1 }
        if indexFromEnd >= fadeFrames { return 1 }
        return Float(indexFromEnd) / Float(fadeFrames)
    }

    // MARK: - Peak guard

    /// クロスフェードで足し合わせたピークが元のピークを超えないための倍率。
    /// 下げる方向だけに使い、音割れを防ぐ。
    static func peakScale(sourcePeak: Float, mixedPeak: Float) -> Float {
        guard sourcePeak > 0, mixedPeak > sourcePeak else { return 1 }
        return sourcePeak / mixedPeak
    }
}

/// 再現可能なシャッフル用の乱数（SplitMix64）。
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
