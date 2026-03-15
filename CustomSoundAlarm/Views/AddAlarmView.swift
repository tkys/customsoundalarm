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

    var body: some View {
        NavigationStack {
            Form {
                timeSection
                labelSection
                repeatSection
                soundSection
            }
            .navigationTitle("アラームを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveAlarm() }
                }
            }
        }
    }

    // MARK: - Sections

    private var timeSection: some View {
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
    }

    private var labelSection: some View {
        Section {
            TextField("ラベル", text: $label)
        }
    }

    private var repeatSection: some View {
        Section("繰り返し") {
            WeekdayPicker(selectedDays: $repeatWeekdays)
        }
    }

    private var soundSection: some View {
        Section("サウンド") {
            if soundStore.sounds.isEmpty {
                Text("先にサウンドを追加してください")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(soundStore.sounds, id: \.id) { sound in
                    SoundRow(sound: sound, isSelected: selectedSound?.id == sound.id) {
                        selectedSound = sound
                    }
                }
            }
        }
    }

    // MARK: - Actions

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

// MARK: - WeekdayPicker

struct WeekdayPicker: View {
    @Binding var selectedDays: Set<Int>

    private let weekdayLabels = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        HStack {
            ForEach(1...7, id: \.self) { day in
                let isSelected = selectedDays.contains(day)
                Button {
                    if isSelected {
                        selectedDays.remove(day)
                    } else {
                        selectedDays.insert(day)
                    }
                } label: {
                    Text(weekdayLabels[day - 1])
                        .font(.caption)
                        .frame(width: 36, height: 36)
                        .background(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.2),
                            in: Circle()
                        )
                        .foregroundStyle(isSelected ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - SoundRow

struct SoundRow: View {
    let sound: AlarmSound
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Label(sound.name, systemImage: "waveform")
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .foregroundStyle(.primary)
    }
}
