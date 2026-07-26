import Foundation
import AlarmKit

/// AlarmKitに渡すカスタムメタデータ
nonisolated struct CustomAlarmMetadata: AlarmMetadata {
    var alarmEntryID: String
    var label: String
    var soundFileName: String
    /// ユーザーが付けたサウンドの表示名。空のときは何も表示しない（UUID.caf を漏らさない）
    var soundDisplayName: String

    init() {
        self.alarmEntryID = ""
        self.label = ""
        self.soundFileName = ""
        self.soundDisplayName = ""
    }

    init(entry: AlarmEntry, soundDisplayName: String = "") {
        self.alarmEntryID = entry.id.uuidString
        self.label = entry.label
        self.soundFileName = entry.soundFileName
        self.soundDisplayName = soundDisplayName
    }

    enum CodingKeys: String, CodingKey {
        case alarmEntryID, label, soundFileName, soundDisplayName
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        alarmEntryID = try container.decode(String.self, forKey: .alarmEntryID)
        label = try container.decode(String.self, forKey: .label)
        soundFileName = try container.decode(String.self, forKey: .soundFileName)
        soundDisplayName = try container.decodeIfPresent(String.self, forKey: .soundDisplayName) ?? ""
    }
}
