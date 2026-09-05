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
    @State private var snoozeMinutes: Int
    @State private var isEnabled: Bool

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
            _snoozeMinutes = State(initialValue: entry.snoozeMinutes)
            _isEnabled = State(initialValue: entry.isEnabled)
        } else {
            _selectedTime = State(initialValue: Date())
            _label = State(initialValue: String(localized: "alarm_placeholder"))
            // 前回保存時に使った音をデフォルト選択（存在しない/削除済みなら nil）
            let initialSound = SoundUsageHistory.lastUsedFileName.flatMap { fileName in
                SoundStore.shared.sounds.first { $0.fileName == fileName }
            }
            _selectedSound = State(initialValue: initialSound)
            _repeatWeekdays = State(initialValue: [])
            _snoozeMinutes = State(initialValue: 9)
            _isEnabled = State(initialValue: true)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                timeSection
                soundSection
                repeatSection
                snoozeSection
                labelSection
                if case .edit = mode {
                    toggleSection
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
                        .disabled(saveConfirmation != nil)
                }
            }
            .overlay(alignment: .top) {
                if let saveConfirmation {
                    SaveConfirmationToast(text: saveConfirmation)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 12)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: saveConfirmation)
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
                            // 1行・末尾省略（#93-2b: 生のファイル名が3行に伸びないようにする）
                            .lineLimit(1)
                            .truncationMode(.tail)
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

    // MARK: - Snooze

    /// クイック選択のチップ（#91-1: よく使う値をワンタップで）
    private let snoozeQuickOptions: [Int] = [1, 2, 5, 10]
    /// 微調整の範囲（0 = オフ。旧選択肢の上限に合わせる）
    private let snoozeRange = 0...30

    private var snoozeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                // 見出し行 + −／＋ の微調整（任意の値は引き続き設定可能）
                HStack {
                    Text("snooze")
                    Spacer()
                    HStack(spacing: 14) {
                        Button {
                            snoozeMinutes = max(snoozeRange.lowerBound, snoozeMinutes - 1)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(snoozeMinutes > snoozeRange.lowerBound ? Color.accentColor : Color.gray.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        .disabled(snoozeMinutes <= snoozeRange.lowerBound)

                        Text(snoozeSummaryText)
                            .monospacedDigit()
                            .frame(minWidth: 48)

                        Button {
                            snoozeMinutes = min(snoozeRange.upperBound, snoozeMinutes + 1)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(snoozeMinutes < snoozeRange.upperBound ? Color.accentColor : Color.gray.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        .disabled(snoozeMinutes >= snoozeRange.upperBound)
                    }
                }

                // クイック選択チップ
                HStack(spacing: 8) {
                    ForEach(snoozeQuickOptions, id: \.self) { minutes in
                        Button {
                            snoozeMinutes = minutes
                        } label: {
                            Text(snoozeText(for: minutes))
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule().fill(
                                        snoozeMinutes == minutes
                                            ? AnyShapeStyle(Brand.saveButtonGradient)
                                            : AnyShapeStyle(Color.accentColor.opacity(0.12))
                                    )
                                )
                                .foregroundStyle(snoozeMinutes == minutes ? .white : Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// チップ・サマリ表示の文言（#91-1）。「N分」形式で任意値にも対応
    private func snoozeText(for minutes: Int) -> String {
        SnoozeDisplay.text(for: minutes)
    }

    private var snoozeSummaryText: String {
        SnoozeDisplay.text(for: snoozeMinutes)
    }

    // MARK: - Toggle

    private var toggleSection: some View {
        Section {
            Toggle(isOn: $isEnabled) {
                Text("alarm_enabled")
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

    /// 保存確定時の確認メッセージ（「7時間30分後に鳴ります」）。nil なら即時閉じる。
    @State private var saveConfirmation: String?

    private func save() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
        let resolvedHour = components.hour ?? 7
        let resolvedMinute = components.minute ?? 0
        let soundFileName = selectedSound?.fileName ?? ""
        let hasCustomSound = selectedSound.map { !$0.isPreset } ?? false
        let isRepeating = !repeatWeekdays.isEmpty

        // サウンド使用履歴を記録（新規作成時のデフォルト選択 + ピッカーの「最近使った」表示用）
        SoundUsageHistory.recordUsage(soundFileName)

        let savedEntry: AlarmEntry

        switch mode {
        case .add:
            let entry = AlarmEntry(
                hour: resolvedHour,
                minute: resolvedMinute,
                label: label,
                repeatWeekdays: Array(repeatWeekdays).sorted(),
                soundFileName: soundFileName,
                snoozeMinutes: snoozeMinutes
            )
            alarmStore.add(entry)
            AnalyticsService.shared.capture(
                .alarmCreated(hasCustomSound: hasCustomSound, isRepeating: isRepeating, snoozeMinutes: snoozeMinutes),
                properties: hoursUntilProperties(for: entry)
            )
            savedEntry = entry
        case .edit(let existing):
            var updated = existing
            updated.hour = resolvedHour
            updated.minute = resolvedMinute
            updated.label = label
            updated.repeatWeekdays = Array(repeatWeekdays).sorted()
            updated.soundFileName = soundFileName
            updated.snoozeMinutes = snoozeMinutes
            updated.isEnabled = isEnabled
            alarmStore.update(updated)
            AnalyticsService.shared.capture(
                .alarmEdited(hasCustomSound: hasCustomSound, isRepeating: isRepeating, snoozeMinutes: snoozeMinutes),
                properties: hoursUntilProperties(for: updated)
            )
            savedEntry = updated
        }

        AlarmScheduler.shared.syncAlarms(alarmStore.alarms)

        // 保存後のフィードバック（ON: 発火までの時間 / OFF: このアラームはオフです）
        let feedback = PostSaveFeedback.resolve(for: savedEntry, currentDate: Date())
        if let message = feedback.localizedMessage(entry: savedEntry, currentDate: Date()) {
            saveConfirmation = message
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                saveConfirmation = nil
                dismiss()
            }
        } else {
            dismiss()
        }
    }

    /// 保存したアラームの次回発火までの時間（整数時間）をアナリティクス用に返す。
    /// 計算不能・無効時は空（プロパティを付与しない）。
    private func hoursUntilProperties(for entry: AlarmEntry) -> [String: Any]? {
        guard entry.isEnabled, let fire = entry.nextFireDate(from: Date()) else { return nil }
        return ["hours_until": AlarmCountdown.hoursUntil(from: Date(), to: fire)]
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

// MARK: - SnoozeDisplay

/// スヌーズ時間の表示文言（#91-1・単体テスト対象）。
/// チップ（1/2/5/10）と −／＋ 微調整の任意値（例: 3分）のどちらにも対応するため
/// 「N分」フォーマットで組み立てる。0 はオフ表記。
enum SnoozeDisplay {
    static func text(for minutes: Int) -> String {
        if minutes == 0 { return String(localized: "snooze_off") }
        return String(format: String(localized: "snooze_minutes_fmt"), minutes)
    }
}

// MARK: - SaveConfirmationToast

/// 保存確定時の「◯時間◯分後に鳴ります」短促トースト。Warm Glow トーンで控えめに。
struct SaveConfirmationToast: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "alarm.waveform.fill")
                .foregroundStyle(Brand.warmGoldGradient)
            Text(text)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        )
    }
}
