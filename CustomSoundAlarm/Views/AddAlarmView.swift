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

    @State private var selectedTime = Date()
    @State private var label = "アラーム"
    @State private var selectedSound: AlarmSound?
    @State private var repeatWeekdays: Set<Int> = []

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
            .navigationTitle(isEditing ? "アラームを編集" : "アラームを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .onAppear { loadFromMode() }
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
                "時刻",
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
                    Text("サウンド")
                    Spacer()
                    Text(selectedSound?.name ?? "なし")
                        .foregroundStyle(.secondary)
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
                    Text("繰り返し")
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
                Text("ラベル")
                TextField("アラーム", text: $label)
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
                    Text("アラームを削除")
                    Spacer()
                }
            }
            .confirmationDialog("このアラームを削除しますか？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    if case .edit(let entry) = mode {
                        alarmStore.remove(entry)
                        Task { await AlarmScheduler.shared.syncAlarms(alarmStore.alarms) }
                    }
                    dismiss()
                }
            }
        }
    }

    // MARK: - Load / Save

    private func loadFromMode() {
        guard case .edit(let entry) = mode else { return }
        var components = DateComponents()
        components.hour = entry.hour
        components.minute = entry.minute
        selectedTime = Calendar.current.date(from: components) ?? Date()
        label = entry.label
        repeatWeekdays = Set(entry.repeatWeekdays)
        selectedSound = soundStore.sounds.first { $0.fileName == entry.soundFileName }
    }

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

        Task { await AlarmScheduler.shared.syncAlarms(alarmStore.alarms) }
        dismiss()
    }

    private var repeatSummary: String {
        if repeatWeekdays.isEmpty { return "しない" }
        let labels = ["日", "月", "火", "水", "木", "金", "土"]
        let days = repeatWeekdays.sorted()
        if days.count == 7 { return "毎日" }
        if repeatWeekdays == Set([2, 3, 4, 5, 6]) { return "平日" }
        if repeatWeekdays == Set([1, 7]) { return "週末" }
        return days.compactMap { d in
            (1...7).contains(d) ? labels[d - 1] : nil
        }.joined(separator: " ")
    }
}

// MARK: - RepeatSelectionView

/// 繰り返し曜日選択（Apple Clock準拠のチェックリスト形式）
struct RepeatSelectionView: View {
    @Binding var selectedDays: Set<Int>

    private let weekdays: [(id: Int, label: String)] = [
        (2, "月曜日"), (3, "火曜日"), (4, "水曜日"),
        (5, "木曜日"), (6, "金曜日"), (7, "土曜日"), (1, "日曜日")
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
                        Text("毎週\(day.label)")
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
        .navigationTitle("繰り返し")
        .navigationBarTitleDisplayMode(.inline)
    }
}
