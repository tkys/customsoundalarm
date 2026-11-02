import Foundation

/// アラームの音の選び方（#151）。
enum PlaylistSoundMode: String, Codable, Sendable, CaseIterable, Equatable, Hashable {
    /// 従来の1つの音
    case single
    /// プレイリストを順番に再生
    case playlistOrder = "playlist_order"
    /// プレイリストをシャッフルして再生
    case playlistShuffle = "playlist_shuffle"
    /// プレイリストから1曲だけランダム
    case playlistRandom = "playlist_random"

    var isPlaylist: Bool {
        self != .single
    }

    /// 停止・起動のたびに次回分を作り直すモード
    var changesOrderOnStop: Bool {
        self == .playlistShuffle || self == .playlistRandom
    }

    /// 計測用の安定識別子（rawValue と同じ）
    var analyticsValue: String { rawValue }
}

/// やさしく鳴り始める長さ（#151）。
enum PlaylistFadeIn: Int, Codable, Sendable, CaseIterable, Equatable, Hashable {
    case off = 0
    case ten = 10
    case thirty = 30
    case sixty = 60

    var seconds: TimeInterval { TimeInterval(rawValue) }

    var analyticsValue: String {
        self == .off ? "off" : String(rawValue)
    }
}

/// 曲間のフェード（#151）。
enum PlaylistGapFade: String, Codable, Sendable, CaseIterable, Equatable, Hashable {
    case off
    case short
    case long
    case crossfade

    /// フェードに使う秒数（off は 0）
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

/// アラームごとのフェード設定（#151）。
struct PlaylistFadeSettings: Codable, Sendable, Equatable, Hashable {
    var fadeIn: PlaylistFadeIn
    var gapFade: PlaylistGapFade
    var endFade: Bool

    init(
        fadeIn: PlaylistFadeIn = .off,
        gapFade: PlaylistGapFade = .off,
        endFade: Bool = false
    ) {
        self.fadeIn = fadeIn
        self.gapFade = gapFade
        self.endFade = endFade
    }

    static let disabled = PlaylistFadeSettings()

    var isDisabled: Bool {
        fadeIn == .off && gapFade == .off && !endFade
    }
}

/// プレイリストの書き出しに必要な入力（#151）。
/// `AlarmEntry` への接続は PR-B で行い、ここではモデルとして独立させる。
struct PlaylistRenderInput: Sendable, Equatable, Hashable {
    let entryID: UUID
    let playlistID: UUID?
    let soundMode: PlaylistSoundMode
    let fadeSettings: PlaylistFadeSettings
    /// プレイリストが無い／単一音のときに使うファイル名
    let fallbackFileName: String

    init(
        entryID: UUID,
        playlistID: UUID? = nil,
        soundMode: PlaylistSoundMode,
        fadeSettings: PlaylistFadeSettings = .disabled,
        fallbackFileName: String = ""
    ) {
        self.entryID = entryID
        self.playlistID = playlistID
        self.soundMode = soundMode
        self.fadeSettings = fadeSettings
        self.fallbackFileName = fallbackFileName
    }

    var usesPlaylistFeatures: Bool {
        soundMode.isPlaylist || !fadeSettings.isDisabled
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

/// ユーザーが作るプレイリスト（#151）。
struct Playlist: Identifiable, Codable, Hashable, Sendable {
    /// 1本のファイルにする都合と容量（10分≒50MB）の上限
    static let maxTotalSeconds: TimeInterval = 10 * 60

    let id: UUID
    var name: String
    var tracks: [PlaylistTrack]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        tracks: [PlaylistTrack] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.tracks = tracks
        self.createdAt = createdAt
    }

    var trackCount: Int { tracks.count }

    /// 曲の長さ（fileName → 秒）から合計時間を返す。不明な曲は 0 として扱う。
    func totalSeconds(durations: [String: TimeInterval]) -> TimeInterval {
        tracks.reduce(0) { $0 + (durations[$1.soundFileName] ?? 0) }
    }
}
