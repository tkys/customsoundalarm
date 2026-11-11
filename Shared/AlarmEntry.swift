import Foundation

/// ユーザーが設定したアラーム1件を表すモデル
struct AlarmEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var hour: Int
    var minute: Int
    var isEnabled: Bool
    var label: String
    /// 繰り返し曜日（1=日〜7=土）、空なら一回限り
    var repeatWeekdays: [Int]
    /// 使用するアラーム音のファイル名
    var soundFileName: String
    /// スヌーズ時間（分）。0 = スヌーズ無効。既定 9分（iOS標準）
    var snoozeMinutes: Int
    /// 最終アラーム（締め切り）までの分数（#110）。nil = オフ。
    /// 旧データには存在しないため `decodeIfPresent` で移行する。
    var backupMinutes: Int?
    /// 使用するプレイリスト（#160）。nil = 1つの音（`soundFileName`）。
    var playlistID: UUID?
    /// やさしく鳴り始める（#160）。アラームが持つ。
    var fadeIn: PlaylistFadeIn
    /// 休む日（ローカル日付の `yyyy-MM-dd`）。その日が過ぎたら自動で消える（#197）。
    /// アラームを「オフ」にはしない。
    var skipDates: [String]
    /// 祝日は鳴らさない（日本のみ・#197）。
    var skipsHolidays: Bool
    /// 祝日でも鳴らす日（`yyyy-MM-dd`・#197）。
    var holidayRingOverrides: [String]

    init(
        id: UUID = UUID(),
        hour: Int = 7,
        minute: Int = 0,
        isEnabled: Bool = true,
        label: String = "アラーム",
        repeatWeekdays: [Int] = [],
        soundFileName: String = "",
        snoozeMinutes: Int = 9,
        backupMinutes: Int? = nil,
        playlistID: UUID? = nil,
        fadeIn: PlaylistFadeIn = .off,
        skipDates: [String] = [],
        skipsHolidays: Bool = false,
        holidayRingOverrides: [String] = []
    ) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.isEnabled = isEnabled
        self.label = label
        self.repeatWeekdays = repeatWeekdays
        self.soundFileName = soundFileName
        self.snoozeMinutes = snoozeMinutes
        self.backupMinutes = backupMinutes
        self.playlistID = playlistID
        self.fadeIn = fadeIn
        self.skipDates = skipDates
        self.skipsHolidays = skipsHolidays
        self.holidayRingOverrides = holidayRingOverrides
    }

    enum CodingKeys: String, CodingKey {
        case id, hour, minute, isEnabled, label, repeatWeekdays, soundFileName, snoozeMinutes, backupMinutes
        case playlistID, fadeIn, skipDates, skipsHolidays, holidayRingOverrides
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        hour = try container.decode(Int.self, forKey: .hour)
        minute = try container.decode(Int.self, forKey: .minute)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        label = try container.decode(String.self, forKey: .label)
        repeatWeekdays = try container.decode([Int].self, forKey: .repeatWeekdays)
        soundFileName = try container.decode(String.self, forKey: .soundFileName)
        snoozeMinutes = try container.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? 9
        backupMinutes = try container.decodeIfPresent(Int.self, forKey: .backupMinutes)
        playlistID = try container.decodeIfPresent(UUID.self, forKey: .playlistID)
        fadeIn = try container.decodeIfPresent(PlaylistFadeIn.self, forKey: .fadeIn) ?? .off
        skipDates = try container.decodeIfPresent([String].self, forKey: .skipDates) ?? []
        skipsHolidays = try container.decodeIfPresent(Bool.self, forKey: .skipsHolidays) ?? false
        holidayRingOverrides = try container.decodeIfPresent([String].self, forKey: .holidayRingOverrides) ?? []
    }

    /// プレイリストか「やさしく鳴り始める」を使っているか（先行公開の権利付与判定・#160）
    var usesPlaylistFeatures: Bool {
        playlistID != nil || fadeIn != .off
    }

    /// プレイリスト書き出しへの入力（#160）
    var playlistRenderInput: PlaylistRenderInput {
        PlaylistRenderInput(
            entryID: id,
            playlistID: playlistID,
            fallbackFileName: soundFileName,
            fadeIn: fadeIn
        )
    }

    var timeString: String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// 次回の発火予定日時を計算する。AlarmKit のスケジュール状態には依存せず、
    /// 純粋に `hour` / `minute` / `repeatWeekdays` と基準日時から算出する。
    ///
    /// - 無効(`isEnabled == false`)、または時/分が範囲外の場合は nil
    /// - 繰り返しなし（一回限り）: 基準日の該当時刻が未来なら当日、過ぎていれば翌日
    /// - 繰り返しあり: `repeatWeekdays`（1=日…7=土）のうち、基準日時以降で最も近い発火日時
    ///
    /// `repeatWeekdays` の番号体系は `Calendar` の weekday と同じ（1=Sunday）。
    /// AlarmKit のスケジュール/発火ロジックには影響しない（表示・計測用）。
    ///
    /// - Parameters:
    ///   - referenceDate: 基準日時（通常は現在時刻）
    ///   - calendar: 計算に用いるカレンダー（デフォルト `.current`）
    /// - Returns: 次回発火予定日時、計算不能なら nil
    func nextFireDate(from referenceDate: Date, calendar: Calendar = .current) -> Date? {
        AlarmSkipLogic.nextFireDate(for: self, after: referenceDate, calendar: calendar)
    }

    /// 複製用の新しいインスタンスを返す。
    /// 新しい `id` を採番し `isEnabled = true` とする（他の設定は同一）。
    /// 元のアラームには影響しない（純粋関数）。
    func duplicated() -> AlarmEntry {
        AlarmEntry(
            id: UUID(),
            hour: hour,
            minute: minute,
            isEnabled: true,
            label: label,
            repeatWeekdays: repeatWeekdays,
            soundFileName: soundFileName,
            snoozeMinutes: snoozeMinutes,
            backupMinutes: backupMinutes,
            playlistID: playlistID,
            fadeIn: fadeIn,
            skipsHolidays: skipsHolidays
        )
    }
}
