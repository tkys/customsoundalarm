import SwiftUI

/// アラーム追加・編集画面
struct AddAlarmView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var alarmStore = AlarmStore.shared
    @State private var soundStore = SoundStore.shared

    @State private var selectedHour = 7
    @State private var selectedMinute = 0
    @State private var label = "アラーム"
    @State private var selectedSound: AlarmSound?
    @State private var repeatWeekdays: Set<Int> = []

    private let weekdayLabels = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - 時刻
                Section {
                    HStack {
                        Picker("時", selection: $selectedHour) {
                            ForEach(0..<24, id: \.self) { h in
                                Text("\(h)").tag(h)
                            }
                        }
                        .pickerStyle(.wheel)

                        Picker("分", selection: $selectedMinute) {
                            ForEach(0..<60, id: \.self) { m in
                                Text(String(format: "%02d", m)).tag(m)
                            }
                        }
                        .pickerStyle(.wheel)
                    }
                    .frame(height: 150)
                }

                // MARK: - ラベル
                Section {
                    TextField("ラベル", text: $label)
                }

                // MARK: - 繰り返し
                Section("繰り返し") {
                    HStack {
                        ForEach(1...7, id: \.self) { day in
                            let index = day - 1
                            Button {
                                if repeatWeekdays.contains(day) {
                                    repeatWeekdays.remove(day)
                                } else {
                                    repeatWeekdays.insert(day)
                                }
                            } label: {
                                Text(weekdayLabels[index])
                                    .font(.caption)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        repeatWeekdays.contains(day)
                                            ? Color.accentColor
                                            : Color.secondary.opacity(0.2),
                                        in: Circle()
                                    )
                                    .foregroundStyle(
                                        repeatWeekdays.contains(day) ? .white : .primary
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // MARK: - サウンド選択
                Section("サウンド") {
                    if soundStore.sounds.isEmpty {
                        Text("先にサウンドを追加してください")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(soundStore.sounds) { sound in
                            Button {
                                selectedSound = sound
                            } label: {
                                HStack {
                                    Label(sound.name, systemImage: "waveform")
                                    Spacer()
                                    if selectedSound?.id == sound.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.accentColor)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("アラームを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveAlarm()
                    }
                }
            }
        }
    }

    private func saveAlarm() {
        let entry = AlarmEntry(
            hour: selectedHour,
            minute: selectedMinute,
            label: label,
            repeatWeekdays: Array(repeatWeekdays).sorted(),
            soundFileName: selectedSound?.fileName ?? ""
        )
        alarmStore.add(entry)
        Task {
            await AlarmScheduler.shared.syncAlarms(alarmStore.alarms)
        }
        dismiss()
    }
}
