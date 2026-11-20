import WidgetKit
import SwiftUI
import AppIntents

/// コントロールセンターからアラーム一覧を開く（#272）。
struct OpenAlarmListControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "OpenAlarmListControl") {
            ControlWidgetButton(
                action: OpenURLIntent(ControlOpenLogic.url(for: .list))
            ) {
                Label("control_open_list", systemImage: "alarm.waves.left.and.right")
            }
        }
        .displayName("control_open_list")
    }
}

/// コントロールセンターからアラーム追加画面を開く（#272）。
struct AddAlarmControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "AddAlarmControl") {
            ControlWidgetButton(
                action: OpenURLIntent(ControlOpenLogic.url(for: .add))
            ) {
                Label("add_alarm", systemImage: "alarm.waves.left.and.right")
            }
        }
        .displayName("add_alarm")
    }
}
