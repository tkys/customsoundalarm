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

    init(
        id: UUID = UUID(),
        hour: Int = 7,
        minute: Int = 0,
        isEnabled: Bool = true,
        label: String = "アラーム",
        repeatWeekdays: [Int] = [],
        soundFileName: String = ""
    ) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.isEnabled = isEnabled
        self.label = label
        self.repeatWeekdays = repeatWeekdays
        self.soundFileName = soundFileName
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
        guard isEnabled else { return nil }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }

        var timeComponents = DateComponents()
        timeComponents.hour = hour
        timeComponents.minute = minute
        timeComponents.second = 0

        // 一回限り: weekday を指定せず「次の hour:minute」を探す。
        // 当日の時刻が未来なら当日、過ぎていれば翌日になる。
        if repeatWeekdays.isEmpty {
            return calendar.nextDate(
                after: referenceDate,
                matching: timeComponents,
                matchingPolicy: .nextTime
            )
        }

        // 繰り返しあり: 該当曜日ごとに「次回発火」を計算し、最も近いものを選ぶ。
        var earliest: Date?
        for weekday in repeatWeekdays {
            guard (1...7).contains(weekday) else { continue }
            var components = timeComponents
            components.weekday = weekday
            guard let candidate = calendar.nextDate(
                after: referenceDate,
                matching: components,
                matchingPolicy: .nextTime
            ) else { continue }
            if earliest == nil || candidate < earliest! {
                earliest = candidate
            }
        }
        return earliest
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
            soundFileName: soundFileName
        )
    }
}
