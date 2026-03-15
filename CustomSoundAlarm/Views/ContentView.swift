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
            .navigationTitle("アラーム")
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
            Label("お気に入りの音で目覚めよう", systemImage: "alarm")
        } description: {
            Text("アラームを追加して、好きな音を設定できます")
        } actions: {
            Button {
                showingAddAlarm = true
            } label: {
                Text("アラームを追加")
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
                        Task { await AlarmScheduler.shared.syncAlarms(alarmStore.alarms) }
                    },
                    onTap: {
                        selectedAlarm = alarm
                    }
                )
            }
            .onDelete { indexSet in
                for index in indexSet {
                    alarmStore.remove(alarmStore.alarms[index])
                }
                Task { await AlarmScheduler.shared.syncAlarms(alarmStore.alarms) }
            }
        }
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
                        .foregroundStyle(alarm.isEnabled ? .primary : .tertiary)

                    HStack(spacing: 6) {
                        Text(alarm.label)
                        Text("・")
                        Text(soundName.isEmpty ? "デフォルト" : soundName)
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
        let labels = ["日", "月", "火", "水", "木", "金", "土"]
        let days = alarm.repeatWeekdays.sorted()
        if days.count == 7 { return "毎日" }
        if days == [2, 3, 4, 5, 6] { return "平日" }
        if days == [1, 7] { return "週末" }
        return days.compactMap { d in
            (1...7).contains(d) ? labels[d - 1] : nil
        }.joined(separator: " ")
    }
}
