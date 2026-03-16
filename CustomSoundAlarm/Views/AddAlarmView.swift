import SwiftUI

// MARK: - Mode

enum AlarmDetailMode: Identifiable {
    case add
    case edit(AlarmEntry)

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let entry): entry.id.uuidString
        }
    }
}

// MARK: - AlarmDetailView

/// アラーム追加・編集画面
/// HIG: DatePickerで時刻選択、サウンドはナビゲーション遷移で選択
struct AlarmDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var alarmStore = AlarmStore.shared
    @State private var soundStore = SoundStore.shared

    let mode: AlarmDetailMode

    @State private var selectedTime: Date
    @State private var label: String
    @State private var selectedSound: AlarmSound?
    @State private var repeatWeekdays: Set<Int>

    init(mode: AlarmDetailMode) {
        self.mode = mode

        if case .edit(let entry) = mode {
            var components = DateComponents()
            components.hour = entry.hour
            components.minute = entry.minute
            _selectedTime = State(initialValue: Calendar.current.date(from: components) ?? Date())
            _label = State(initialValue: entry.label)
            _repeatWeekdays = State(initialValue: Set(entry.repeatWeekdays))
            _selectedSound = State(
                initialValue: SoundStore.shared.sounds.first { $0.fileName == entry.soundFileName }
            )
        } else {
            _selectedTime = State(initialValue: Date())
            _label = State(initialValue: String(localized: "alarm_placeholder"))
            _selectedSound = State(initialValue: nil)
            _repeatWeekdays = State(initialValue: [])
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                timeSection
                soundSection
                repeatSection
                labelSection
                if case .edit = mode {
                    deleteSection
                }
            }
            .warmListBackground()
            .navigationTitle(isEditing ? String(localized: "edit_alarm") : String(localized: "add_alarm"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save") { save() }
                }
            }
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    // MARK: - Time (HIG: DatePicker)

    private var timeSection: some View {
        Section {
            DatePicker(
                "time",
                selection: $selectedTime,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
        }
    }

    // MARK: - Sound (OOUI: アラームのプロパティとしてアクセス)

    private var soundSection: some View {
        Section {
            NavigationLink {
                SoundSelectionView(selectedSound: $selectedSound)
            } label: {
                HStack {
                    Text("sound")
                    Spacer()
                    HStack(spacing: 4) {
                        SoundIndicator(
                            isCustom: selectedSound != nil && !(selectedSound?.isPreset ?? true),
                            size: 12
                        )
                        Text(selectedSound?.name ?? String(localized: "none"))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Repeat

    private var repeatSection: some View {
        Section {
            NavigationLink {
                RepeatSelectionView(selectedDays: $repeatWeekdays)
            } label: {
                HStack {
                    Text("repeat")
                    Spacer()
                    Text(repeatSummary)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Label

    private var labelSection: some View {
        Section {
            HStack {
                Text("label")
                TextField("alarm_placeholder", text: $label)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    // MARK: - Delete

    @State private var showingDeleteConfirmation = false

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    Text("delete_alarm")
                    Spacer()
                }
            }
            .confirmationDialog("delete_alarm_confirm", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("delete", role: .destructive) {
                    if case .edit(let entry) = mode {
                        alarmStore.remove(entry)
                        AlarmScheduler.shared.syncAlarms(alarmStore.alarms)
                    }
                    dismiss()
                }
            }
        }
    }

    // MARK: - Save

    private func save() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)

        switch mode {
        case .add:
            let entry = AlarmEntry(
                hour: components.hour ?? 7,
                minute: components.minute ?? 0,
                label: label,
                repeatWeekdays: Array(repeatWeekdays).sorted(),
                soundFileName: selectedSound?.fileName ?? ""
            )
            alarmStore.add(entry)
        case .edit(let existing):
            var updated = existing
            updated.hour = components.hour ?? existing.hour
            updated.minute = components.minute ?? existing.minute
            updated.label = label
            updated.repeatWeekdays = Array(repeatWeekdays).sorted()
            updated.soundFileName = selectedSound?.fileName ?? ""
            alarmStore.update(updated)
        }

        AlarmScheduler.shared.syncAlarms(alarmStore.alarms)
        dismiss()
    }

    private var repeatSummary: String {
        if repeatWeekdays.isEmpty { return String(localized: "never") }
        let labels = [
            String(localized: "day_sun"), String(localized: "day_mon"),
            String(localized: "day_tue"), String(localized: "day_wed"),
            String(localized: "day_thu"), String(localized: "day_fri"),
            String(localized: "day_sat")
        ]
        let days = repeatWeekdays.sorted()
        if days.count == 7 { return String(localized: "every_day") }
        if repeatWeekdays == Set([2, 3, 4, 5, 6]) { return String(localized: "weekdays") }
        if repeatWeekdays == Set([1, 7]) { return String(localized: "weekends") }
        return days.compactMap { d in
            (1...7).contains(d) ? labels[d - 1] : nil
        }.joined(separator: " ")
    }
}

// MARK: - RepeatSelectionView

/// 繰り返し曜日選択（Apple Clock準拠のチェックリスト形式）
struct RepeatSelectionView: View {
    @Binding var selectedDays: Set<Int>

    private let weekdays: [(id: Int, labelKey: String)] = [
        (2, "every_monday"), (3, "every_tuesday"), (4, "every_wednesday"),
        (5, "every_thursday"), (6, "every_friday"), (7, "every_saturday"), (1, "every_sunday")
    ]

    var body: some View {
        List {
            ForEach(weekdays, id: \.id) { day in
                Button {
                    if selectedDays.contains(day.id) {
                        selectedDays.remove(day.id)
                    } else {
                        selectedDays.insert(day.id)
                    }
                } label: {
                    HStack {
                        Text(String(localized: String.LocalizationValue(day.labelKey)))
                        Spacer()
                        if selectedDays.contains(day.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .warmListBackground()
        .navigationTitle(String(localized: "repeat"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
