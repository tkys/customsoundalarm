import Foundation

/// SoundAnalysis の1窓ぶんの上位ラベル。
struct SoundKindLabelConfidence: Sendable, Equatable {
    let label: String
    let confidence: Double
}

/// SoundAnalysis の1窓。`startSeconds` は音声の先頭からの秒。
struct SoundKindWindow: Sendable, Equatable {
    let startSeconds: Double
    let top: [SoundKindLabelConfidence]
}

/// 判定の結果。
struct SoundKindAnalysisResult: Sendable, Equatable {
    /// 保存形式の版。判定規則を変えたら上げる（#202）。
    static let currentVersion = 1

    static let unknown = SoundKindAnalysisResult(
        contentKind: .unknown,
        bpm: nil,
        vocalStartSeconds: nil,
        analysisVersion: currentVersion
    )

    let contentKind: SoundContentKind
    let bpm: Int?
    let vocalStartSeconds: Double?
    let analysisVersion: Int
}

/// 窓の結果から区分を決める（sound-kind-lab/scripts/run.py の vocal_share と decide）。
enum SoundKindDecision {
    /// 窓ごとのラベルの自信の下限。
    static let minimumConfidence = 0.3
    /// 歌声の窓がこの割合以上なら singing。
    static let vocalMinimumShare = 0.2

    struct Result: Sendable, Equatable {
        let contentKind: SoundContentKind
        let vocalStartSeconds: Double?
    }

    static func decide(windows: [SoundKindWindow]) -> Result {
        guard !windows.isEmpty else {
            return Result(contentKind: .unknown, vocalStartSeconds: nil)
        }

        // 歌：歌声のラベルが自信0.3以上で上位3のどれかに入る窓が2割以上。
        // 市販の曲は1位が music になり、歌声は2〜3位に隠れるため。
        let vocalWindows = windows.filter { window in
            window.top.contains { item in
                SoundKindLabelMap.singing.contains(item.label)
                    && item.confidence >= minimumConfidence
            }
        }
        let vocalShare = Double(vocalWindows.count) / Double(windows.count)
        if vocalShare >= vocalMinimumShare {
            return Result(
                contentKind: .singing,
                vocalStartSeconds: vocalWindows.map(\.startSeconds).min()
            )
        }

        // それ以外：窓ごとの1位を区分に置き換え、いちばん多い区分を答えにする。
        // 自信0.3以上の窓が1つも無ければ unknown。窓はあるが7区分に当たらなければ other。
        // 7区分に当たる窓が1つでもあれば、run.py と同じくその中でいちばん多い区分を選ぶ。
        var validWindowCount = 0
        var counts: [SoundContentKind: Int] = [:]
        var order: [SoundContentKind] = []
        for window in windows {
            guard let top = window.top.first,
                  top.confidence >= minimumConfidence else { continue }
            validWindowCount += 1
            let kind = SoundKindLabelMap.kind(for: top.label)
            guard kind != .other else { continue }
            if counts[kind] == nil { order.append(kind) }
            counts[kind, default: 0] += 1
        }
        guard validWindowCount > 0 else {
            return Result(contentKind: .unknown, vocalStartSeconds: nil)
        }
        guard var best = order.first else {
            return Result(contentKind: .other, vocalStartSeconds: nil)
        }
        var bestCount = counts[best] ?? 0
        for kind in order.dropFirst() {
            let count = counts[kind] ?? 0
            if count > bestCount {
                best = kind
                bestCount = count
            }
        }
        return Result(contentKind: best, vocalStartSeconds: nil)
    }
}

/// 303ラベルを SoundContentKind にまとめる（sound-kind-lab/groups.json が元）。
/// 歌・歌の無い曲・声・猫・犬・鳥・自然音だけを残し、それ以外は other。
enum SoundKindLabelMap {
    static let singing: Set<String> = [
        "singing", "choir_singing", "rapping", "humming", "yodeling"
    ]

    static func kind(for label: String) -> SoundContentKind {
        if cat.contains(label) { return .cat }
        if dog.contains(label) { return .dog }
        if bird.contains(label) { return .bird }
        if voice.contains(label) { return .voice }
        if singing.contains(label) { return .singing }
        if instrumental.contains(label) { return .instrumental }
        if nature.contains(label) { return .nature }
        return .other
    }

    static let cat: Set<String> = [
        "cat", "cat_meow", "cat_purr"
    ]

    static let dog: Set<String> = [
        "dog", "dog_bark", "dog_bow_wow", "dog_growl",
        "dog_howl", "dog_whimper"
    ]

    static let bird: Set<String> = [
        "bird", "bird_chirp_tweet", "bird_flapping", "bird_squawk",
        "bird_vocalization", "rooster_crow", "crow_caw", "owl_hoot",
        "pigeon_dove_coo", "chicken", "chicken_cluck", "duck_quack",
        "goose_honk", "turkey_gobble", "fowl"
    ]

    /// baby_child と speech をまとめた「声」。
    static let voice: Set<String> = [
        "babble", "baby_crying", "baby_laughter", "battle_cry",
        "belly_laugh", "chatter", "children_shouting", "chuckle_chortle",
        "crowd", "giggling", "laughter", "screaming",
        "shout", "snicker", "speech", "whispering",
        "yell"
    ]

    static let instrumental: Set<String> = [
        "music", "accordion", "acoustic_guitar", "bagpipes",
        "banjo", "bass_drum", "bass_guitar", "bassoon",
        "bowed_string_instrument", "brass_instrument", "cello", "clarinet",
        "cowbell", "cymbal", "didgeridoo", "double_bass",
        "drum", "drum_kit", "electric_guitar", "electric_piano",
        "electronic_organ", "flute", "french_horn", "glockenspiel",
        "gong", "guitar", "guitar_strum", "guitar_tapping",
        "hammond_organ", "harmonica", "harp", "harpsichord",
        "hi_hat", "keyboard_musical", "mallet_percussion", "mandolin",
        "marimba_xylophone", "oboe", "orchestra", "organ",
        "percussion", "piano", "plucked_string_instrument", "rattle_instrument",
        "saxophone", "shofar", "singing_bowl", "sitar",
        "snare_drum", "steel_guitar_slide_guitar", "steelpan", "synthesizer",
        "tabla", "tambourine", "theremin", "timpani",
        "trombone", "trumpet", "tuning_fork", "ukulele",
        "vibraphone", "violin_fiddle", "wind_instrument", "zither",
        "disc_scratching"
    ]

    static let nature: Set<String> = [
        "rain", "raindrop", "thunder", "thunderstorm",
        "ocean", "sea_waves", "stream_burbling", "waterfall",
        "water", "wind", "wind_rustling_leaves", "wind_noise_microphone",
        "fire", "fire_crackle", "underwater_bubbling"
    ]
}
