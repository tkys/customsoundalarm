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
}
