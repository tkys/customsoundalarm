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

                    switch context.state.mode {
                    case .countdown(let mode):
                        Text(mode.fireDate, style: .timer)
                            .font(.title2.monospacedDigit())
                            .foregroundStyle(.orange)
                    case .alert, .paused:
                        EmptyView()
                    @unknown default:
                        EmptyView()
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
                DynamicIslandExpandedRegion(.trailing) {
                    switch context.state.mode {
                    case .countdown(let mode):
                        Text(mode.fireDate, style: .timer)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.orange)
                    case .alert, .paused:
                        EmptyView()
                    @unknown default:
                        EmptyView()
                    }
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                switch context.state.mode {
                case .countdown(let mode):
                    Text(mode.fireDate, style: .timer)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.orange)
                case .alert, .paused:
                    Text(metadata?.label ?? "")
                        .font(.caption)
                @unknown default:
                    Text(metadata?.label ?? "")
                        .font(.caption)
                }
            } minimal: {
                switch context.state.mode {
                case .countdown:
                    Image(systemName: "alarm.fill")
                        .foregroundStyle(.orange)
                case .alert, .paused:
                    Image(systemName: "alarm.fill")
                        .foregroundStyle(.red)
                @unknown default:
                    Image(systemName: "alarm.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
