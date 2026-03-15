import WidgetKit
import SwiftUI
import AlarmKit

struct AlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<CustomAlarmMetadata>.self) { context in
            // Lock Screen UI
            if let metadata = context.attributes.metadata {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "alarm.fill")
                            .foregroundStyle(.orange)
                        Text(metadata.label)
                            .font(.headline)
                    }

                    if !metadata.soundFileName.isEmpty {
                        Text(metadata.soundFileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
        } dynamicIsland: { context in
            let metadata = context.attributes.metadata

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill")
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(metadata?.label ?? "")
                        .font(.headline)
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                Text(metadata?.label ?? "")
                    .font(.caption)
            } minimal: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}
