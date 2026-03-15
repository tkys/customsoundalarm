import WidgetKit
import SwiftUI
import AlarmKit

struct AlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        AlarmActivityConfiguration(for: CustomAlarmMetadata.self) { context in
            // Lock Screen UI
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "alarm.fill")
                        .foregroundStyle(.orange)
                    Text(context.state.metadata.label)
                        .font(.headline)
                }

                if !context.state.metadata.soundFileName.isEmpty {
                    Text(context.state.metadata.soundFileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill")
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.metadata.label)
                        .font(.headline)
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                Text(context.state.metadata.label)
                    .font(.caption)
            } minimal: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}
