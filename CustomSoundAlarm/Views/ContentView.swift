import SwiftUI

/// メイン画面：アラーム一覧
/// OOUIの原則に従い、主オブジェクト（アラーム）のみを表示
struct ContentView: View {
    @State private var alarmStore = AlarmStore.shared
    @State private var soundStore = SoundStore.shared
    @State private var selectedAlarm: AlarmEntry?
    @State private var showingAddAlarm = false

    var body: some View {
        NavigationStack {
            Group {
                if alarmStore.alarms.isEmpty {
                    emptyState
                } else {
                    alarmList
                }
            }
            .navigationTitle(String(localized: "alarm_title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddAlarm = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddAlarm) {
                AlarmDetailView(mode: .add)
            }
            .sheet(item: $selectedAlarm) { alarm in
                AlarmDetailView(mode: .edit(alarm))
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("empty_title")
            } icon: {
                SoundWaveDecoration()
                    .padding(.bottom, 4)
            }
        } description: {
            VStack(spacing: 8) {
                Text("empty_description")
                HStack(spacing: 4) {
                    Image(systemName: "video.badge.waveform")
                    Text("・")
                    Image(systemName: "doc.badge.plus")
                    Text("empty_tip")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } actions: {
            Button {
                showingAddAlarm = true
            } label: {
                Text("add_alarm")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Alarm List

    private var alarmList: some View {
        List {
            ForEach(alarmStore.alarms, id: \.id) { alarm in
                AlarmRow(
                    alarm: alarm,
                    soundName: soundStore.displayName(for: alarm.soundFileName),
                    onToggle: {
                        alarmStore.toggleEnabled(alarm)
                        AlarmScheduler.shared.syncAlarms(alarmStore.alarms)
                    },
                    onTap: {
                        selectedAlarm = alarm
                    }
                )
                .warmCard()
            }
            .onDelete { indexSet in
                for index in indexSet {
                    alarmStore.remove(alarmStore.alarms[index])
                }
                AlarmScheduler.shared.syncAlarms(alarmStore.alarms)
            }
        }
        .warmListBackground()
    }

}

// MARK: - AlarmRow

struct AlarmRow: View {
    let alarm: AlarmEntry
    let soundName: String
    let onToggle: () -> Void
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(alarm.timeString)
                        .font(.system(size: 44, weight: .light, design: .rounded))
                        .foregroundStyle(
                            alarm.isEnabled
                                ? AnyShapeStyle(Brand.warmGoldGradient)
                                : AnyShapeStyle(.tertiary)
                        )

                    HStack(spacing: 6) {
                        Text(alarm.label)
                        Text("・")
                        SoundIndicator(isCustom: !alarm.soundFileName.isEmpty, size: 10)
                        Text(soundName.isEmpty ? String(localized: "default_sound") : soundName)
                        if !alarm.repeatWeekdays.isEmpty {
                            Text("・")
                            Text(repeatSummary)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(alarm.isEnabled ? .secondary : .tertiary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { alarm.isEnabled },
                    set: { _ in onToggle() }
                ))
                .labelsHidden()
            }
            .padding(.vertical, 4)
        }
        .foregroundStyle(.primary)
    }

    private var repeatSummary: String {
        let labels = [
            String(localized: "day_sun"), String(localized: "day_mon"),
            String(localized: "day_tue"), String(localized: "day_wed"),
            String(localized: "day_thu"), String(localized: "day_fri"),
            String(localized: "day_sat")
        ]
        let days = alarm.repeatWeekdays.sorted()
        if days.count == 7 { return String(localized: "every_day") }
        if days == [2, 3, 4, 5, 6] { return String(localized: "weekdays") }
        if days == [1, 7] { return String(localized: "weekends") }
        return days.compactMap { d in
            (1...7).contains(d) ? labels[d - 1] : nil
        }.joined(separator: " ")
    }
}
