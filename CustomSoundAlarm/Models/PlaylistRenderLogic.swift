import Foundation

/// プレイリストの並び・長さ・フェードの純ロジック（#151）。
/// 実ファイルの読み書きは `PlaylistRenderer` が行う。
enum PlaylistRenderLogic {
    static let sampleRate: Double = 44_100
    /// ループのつなぎ目を常に短くフェードアウトする（#160）
    static let endFadeSeconds: TimeInterval = 0.5

    // MARK: - Order

    /// 再生順に応じた曲順を返す。
    /// - `.shuffle` は固定シードで再現可能
    /// - `.oneRandom` は候補から1曲
    /// - Parameter avoidingPreviousOrder: シャッフルで前回と同じ並びを避ける
    ///   （曲が2曲以上のとき・#169）。前回の曲 ID 順を渡す。
    static func orderedTracks(
        _ tracks: [PlaylistTrack],
        order: PlaylistPlayOrder,
        seed: UInt64,
        avoidingPreviousOrder previousOrder: [UUID] = []
    ) -> [PlaylistTrack] {
        switch order {
        case .inOrder:
            return tracks
        case .shuffle:
            guard tracks.count > 1 else { return tracks }
            var generator = SplitMix64(seed: seed)
            let shuffled = tracks.shuffled(using: &generator)
            guard !previousOrder.isEmpty,
                  shuffled.map(\.id) == previousOrder else {
                return shuffled
            }
            // 偶然同じ順になったら末尾2曲を入れ替える（2曲でも保証）。
            // 先頭を末尾へ回すだけだと、ループ再生では同じ並びに聞こえるため。
            var adjusted = shuffled
            adjusted.swapAt(adjusted.count - 1, adjusted.count - 2)
            return adjusted
        case .oneRandom:
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
        transition: PlaylistTransition
    ) -> TimeInterval {
        let sum = trackDurations.reduce(0) { $0 + max(0, $1) }
        guard transition == .crossfade else { return sum }
        return max(0, sum - crossfadeOverlap(
            trackDurations: trackDurations,
            seconds: PlaylistTransition.crossfade.seconds
        ))
    }

    /// 10分以内か（浮動小数の誤差を許容）
    static func isWithinLimit(
        trackDurations: [TimeInterval],
        transition: PlaylistTransition
    ) -> Bool {
        totalDuration(trackDurations: trackDurations, transition: transition)
            <= Playlist.maxTotalSeconds + 0.001
    }

    // MARK: - Fade-in repeat (#181)

    /// 繰り返し対象にする1周の最大長。これを超える音源は1周で十分に大きくなる。
    static let maxRepeatedCycleDuration: TimeInterval = 60

    /// やさしく鳴り始める用の繰り返し回数（#181）。
    ///
    /// 1周の長さ `L` が 60 秒以下なら、設定秒数をかけて最大音量に届き、
    /// 最大音量で最低1周分鳴るように `ceil(fadeSeconds / L) + 1` 周にする。
    /// 60 秒超は1周のまま（30 秒で最大に届き、最大音量で30秒以上鳴る）。
    /// オフ・寝過ごし防止用（`applyFadeIn == false`）は繰り返さない。
    static func fadeInCycleCount(
        cycleDuration: TimeInterval,
        fadeIn: PlaylistFadeIn,
        applyFadeIn: Bool
    ) -> Int {
        guard applyFadeIn,
              fadeIn != .off,
              cycleDuration > 0,
              cycleDuration <= maxRepeatedCycleDuration else {
            return 1
        }
        return Int(ceil(fadeIn.seconds / cycleDuration)) + 1
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

    // MARK: - Crossfade

    /// 線形クロスフェードの1サンプル。
    /// `|a(1-m)+b*m| <= max(|a|,|b|)` なので、ピーク補正は不要。
    static func crossfadeMix(a: Float, b: Float, mix: Float) -> Float {
        a * (1 - mix) + b * mix
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

/// 書き出し失敗時のフォールバック先を決める純ロジック（#151）。
/// 存在する最初の曲 → 入力の音 → 既定のプリセット、の順。
enum PlaylistFallbackLogic {
    static func fileName(
        tracks: [PlaylistTrack],
        fallbackFileName: String,
        isAvailable: (String) -> Bool,
        defaultFileName: String
    ) -> String {
        if let track = tracks.first(where: { isAvailable($0.soundFileName) }) {
            return track.soundFileName
        }
        if isAvailable(fallbackFileName) {
            return fallbackFileName
        }
        return defaultFileName
    }
}
