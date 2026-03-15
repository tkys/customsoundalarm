import Foundation
import AlarmKit

/// AlarmKitに渡すカスタムメタデータ
nonisolated struct CustomAlarmMetadata: AlarmMetadata {
    var alarmEntryID: String
    var label: String
    var soundFileName: String

    init() {
        self.alarmEntryID = ""
        self.label = ""
        self.soundFileName = ""
    }

    init(entry: AlarmEntry) {
        self.alarmEntryID = entry.id.uuidString
        self.label = entry.label
        self.soundFileName = entry.soundFileName
    }
}
