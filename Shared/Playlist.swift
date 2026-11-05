import Foundation

/// 計測用の音の選び方（#151 / #160）。アラームとプレイリストから導出する。
enum PlaylistSoundMode: String, Codable, Sendable, CaseIterable, Equatable, Hashable {
    case single
    case playlistOrder = "playlist_order"
    case playlistShuffle = "playlist_shuffle"
    case playlistRandom = "playlist_random"

    var isPlaylist: Bool {
        self != .single
    }

    var changesOrderOnStop: Bool {
        self == .playlistShuffle || self == .playlistRandom
    }

    var analyticsValue: String { rawValue }
}

/// やさしく鳴り始める長さ（#151 / #160 / #181）。アラームが持つ。
enum PlaylistFadeIn: Int, Codable, Sendable, CaseIterable, Equatable, Hashable {
    case off = 0
    case five = 5
    case fifteen = 15
    case thirty = 30

    var seconds: TimeInterval { TimeInterval(rawValue) }

    var analyticsValue: String {
        self == .off ? "off" : String(rawValue)
    }

    /// 旧バージョンの値も読み込めるようにする（#181）。
    /// - 10秒 → 15秒
    /// - 60秒 → 30秒
    /// - それ以外の未知の値 → オフ
    ///
    /// enum の自動 Codable は未知の raw value で throw するため、
    /// 保存済みアラーム全体の読み込みを止めないよう独自に decode する。
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(Int.self)
        switch raw {
        case 5: self = .five
        case 15: self = .fifteen
        case 30: self = .thirty
        case 10: self = .fifteen
        case 60: self = .thirty
        default: self = .off
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// プレイリストの再生順（#160）。プレイリストが持つ。
enum PlaylistPlayOrder: String, Codable, Sendable, CaseIterable, Equatable, Hashable {
    case inOrder = "in_order"
    case shuffle
    case oneRandom = "one_random"

    /// アラームの計測用 `sound_mode` への変換
    var soundMode: PlaylistSoundMode {
        switch self {
        case .inOrder: .playlistOrder
        case .shuffle: .playlistShuffle
        case .oneRandom: .playlistRandom
        }
    }

    var changesOrderOnStop: Bool {
        self == .shuffle || self == .oneRandom
    }

    var analyticsValue: String { rawValue }
}

/// プレイリストの曲のつなぎ方（#160）。
enum PlaylistTransition: String, Codable, Sendable, CaseIterable, Equatable, Hashable {
    case off
    case short
    case long
    case crossfade

    var seconds: TimeInterval {
        switch self {
        case .off: 0
        case .short: 0.5
        case .long: 2
        case .crossfade: 2
        }
    }

    var analyticsValue: String { rawValue }
}

/// プレイリストの書き出しに必要な入力（#151 / #160）。
/// 再生順・つなぎ方は `Playlist` から、やさしく鳴り始めるはアラームから取る。
struct PlaylistRenderInput: Sendable, Equatable, Hashable {
    let entryID: UUID
    let playlistID: UUID?
    let fallbackFileName: String
    let fadeIn: PlaylistFadeIn

    init(
        entryID: UUID,
        playlistID: UUID? = nil,
        fallbackFileName: String = "",
        fadeIn: PlaylistFadeIn = .off
    ) {
        self.entryID = entryID
        self.playlistID = playlistID
        self.fallbackFileName = fallbackFileName
        self.fadeIn = fadeIn
    }

    var isPlaylist: Bool { playlistID != nil }

    var usesPlaylistFeatures: Bool {
        playlistID != nil || fadeIn != .off
    }
}

/// プレイリスト内の1曲（#151）。`soundFileName` は SoundStore の fileName。
struct PlaylistTrack: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var soundFileName: String

    init(id: UUID = UUID(), soundFileName: String) {
        self.id = id
        self.soundFileName = soundFileName
    }
}

/// ユーザーが作るプレイリスト（#151 / #160）。
struct Playlist: Identifiable, Codable, Hashable, Sendable {
    /// 1本のファイルにする都合と容量（10分≒50MB）の上限
    static let maxTotalSeconds: TimeInterval = 10 * 60

    let id: UUID
    var name: String
    var tracks: [PlaylistTrack]
    /// 再生順（プレイリストの性質）
    var playOrder: PlaylistPlayOrder
    /// 曲のつなぎ方（プレイリストの性質）
    var transition: PlaylistTransition
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        tracks: [PlaylistTrack] = [],
        playOrder: PlaylistPlayOrder = .inOrder,
        transition: PlaylistTransition = .off,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.tracks = tracks
        self.playOrder = playOrder
        self.transition = transition
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, tracks, playOrder, transition, createdAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        tracks = try container.decode([PlaylistTrack].self, forKey: .tracks)
        playOrder = try container.decodeIfPresent(
            PlaylistPlayOrder.self,
            forKey: .playOrder
        ) ?? .inOrder
        transition = try container.decodeIfPresent(
            PlaylistTransition.self,
            forKey: .transition
        ) ?? .off
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    var trackCount: Int { tracks.count }

    /// 曲の長さ（fileName → 秒）から合計時間を返す。不明な曲は 0 として扱う。
    func totalSeconds(durations: [String: TimeInterval]) -> TimeInterval {
        tracks.reduce(0) { $0 + (durations[$1.soundFileName] ?? 0) }
    }
}

/// アラームの `sound_mode` を、アラームとプレイリストから導出する純ロジック（#160）。
enum AlarmSoundModeLogic {
    static func soundMode(
        playlistID: UUID?,
        playOrder: PlaylistPlayOrder?
    ) -> PlaylistSoundMode {
        guard playlistID != nil else { return .single }
        return (playOrder ?? .inOrder).soundMode
    }
}
