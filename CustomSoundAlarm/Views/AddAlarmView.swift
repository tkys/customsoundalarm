import SwiftUI
import UIKit

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
    @Environment(\.openURL) private var openURL
    @State private var alarmStore = AlarmStore.shared
    @State private var soundStore = SoundStore.shared
    @State private var scheduler = AlarmScheduler.shared

    let mode: AlarmDetailMode
    /// オンボ場面4からの指定（#98 Phase 4）。
    /// video/audio → 表示直後にサウンド選択を開き該当の取り込みを直接開く。
    /// preset → プリセット先頭を選択済みにする。nil なら従来どおり
    var initialImport: OnboardingSource?

    @State private var selectedTime: Date
    @State private var label: String
    @State private var selectedSound: AlarmSound?
    @State private var repeatWeekdays: Set<Int>
    @State private var snoozeMinutes: Int
    @State private var backupMinutes: Int?

    /// オンボ指定の初期動作を1回だけ適用したか
    @State private var didApplyInitialImport = false
    /// 取り込み提示（#101 B: 追加画面に直接出す）
    @State private var isImporting = false
    @State private var pendingAudio: PendingAudioImport?
    @State private var showingVideoImport = false
    @State private var importErrorMessage: String?

    /// 試しに鳴らす（#109）
    @State private var isSchedulingTestRing = false
    @State private var testRingMessage: String?
    @State private var backupTestRingMessage: String?

    /// 音量の案内（#121）・寝過ごし防止の説明（#122）
    @State private var showingVolumeGuide = false
    @State private var showingBackupInfo = false

    init(mode: AlarmDetailMode, initialImport: OnboardingSource? = nil) {
        self.mode = mode
        self.initialImport = initialImport

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
            _backupMinutes = State(initialValue: entry.backupMinutes)
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
            _backupMinutes = State(initialValue: nil)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if !scheduler.canScheduleTestRing {
                    permissionSection
                }
                timeSection
                repeatSection
                labelSection
                soundSection
                testRingSection
                snoozeSection
                backupAlarmSection
                if case .edit = mode {
                    deleteSection
                }
            }
            .accessibilityIdentifier("addAlarm.root")
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
            .soundImport(
                selectedSound: $selectedSound,
                isImporting: $isImporting,
                pendingAudio: $pendingAudio,
                showingVideoImport: $showingVideoImport,
                errorMessage: $importErrorMessage
            )
            .task {
                scheduler.refreshTestRingPermission()
                // 追加画面のシート提示完了後に取り込みを開く（約0.35秒待つ）
                try? await Task.sleep(for: .milliseconds(500))
                applyInitialImportOnce()
            }
            .onAppear {
                scheduler.refreshTestRingPermission()
            }
            .sheet(isPresented: $showingVolumeGuide) {
                AlarmVolumeGuideView(source: .testRing)
            }
            .sheet(isPresented: $showingBackupInfo) {
                BackupAlarmInfoView()
                    .presentationDetents([.medium])
            }
            .alert("error", isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )) {
                Button("ok", role: .cancel) { importErrorMessage = nil }
            } message: {
                if let importErrorMessage {
                    Text(importErrorMessage)
                }
            }
        }
    }

    /// オンボ指定の初期動作を1回だけ適用する（#101 B: 追加画面に直接出す）
    private func applyInitialImportOnce() {
        guard !didApplyInitialImport else { return }
        didApplyInitialImport = true
        switch OnboardingLogic.initialImportAction(for: initialImport) {
        case .openVideoImport:
            showingVideoImport = true
        case .openFileImporter:
            isImporting = true
        case .preselectPreset:
            if selectedSound == nil {
                selectedSound = soundStore.sounds.first(where: \.isPreset)
            }
        case .none:
            break
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
                            .accessibilityIdentifier("addAlarm.soundName")
                            // 1行・末尾省略（#93-2b: 生のファイル名が3行に伸びないようにする）
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .accessibilityIdentifier("addAlarm.soundRow")
        }
    }

    // MARK: - Permission (#122)

    private var permissionSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("alarm_permission_required")
                Spacer()
                Button("open_settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .accessibilityIdentifier("addAlarm.openSettings")
            }
            .accessibilityIdentifier("addAlarm.permissionRow")
        }
    }

    // MARK: - Oversleep guard (#110 / #122)

    private var isBackupAvailable: Bool {
        BackupAlarmAccess.isAvailable(
            isPro: Entitlements.shared.isPro,
            earlyAccessGranted: AppGroup.backupEarlyAccessGranted
        )
    }

    private var backupToggle: Binding<Bool> {
        Binding(
            get: { backupMinutes != nil },
            set: { isOn in
                if isOn {
                    backupMinutes = backupMinutes ?? BackupAlarmLogic.defaultMinutes
                    if BackupAlarmAccess.shouldGrantEarlyAccess(isEnabled: true) {
                        AppGroup.backupEarlyAccessGranted = true
                    }
                } else {
                    backupMinutes = nil
                }
            }
        )
    }

    private var backupAlarmSection: some View {
        Section {
            HStack(spacing: 8) {
                Text("backup_alarm_toggle")
                badge("PRO")
                Button {
                    showingBackupInfo = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("backup_alarm_info_accessibility"))
                .accessibilityIdentifier("addAlarm.backupInfo")

                Spacer()

                Toggle("", isOn: backupToggle)
                    .labelsHidden()
                    .accessibilityLabel(Text("backup_alarm_toggle"))
                    .accessibilityIdentifier("addAlarm.backupToggle")
                    // 使えない環境でも、既にオンならオフにはできる
                    .disabled(!isBackupAvailable && backupMinutes == nil)
            }

            if let minutes = backupMinutes {
                Picker("backup_alarm_minutes", selection: Binding(
                    get: { backupMinutes ?? BackupAlarmLogic.defaultMinutes },
                    set: { backupMinutes = $0 }
                )) {
                    ForEach(BackupAlarmLogic.minuteOptions, id: \.self) { option in
                        Text(String(format: String(localized: "backup_alarm_minutes_fmt"), option))
                            .tag(option)
                    }
                }
                .accessibilityIdentifier("addAlarm.backupMinutes")

                Button {
                    scheduleTestRing(kind: .backup)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "speaker.wave.3.fill")
                        Text("test_ring_backup_title")
                        Spacer()
                        if isSchedulingTestRing {
                            ProgressView()
                        }
                    }
                }
                .disabled(!scheduler.canScheduleTestRing || isSchedulingTestRing)
                .accessibilityIdentifier("addAlarm.backupTestRing")

                if let backupTestRingMessage {
                    Text(backupTestRingMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            if let minutes = backupMinutes {
                VStack(alignment: .leading, spacing: 4) {
                    Text(backupDescriptionText)
                    if minutes <= snoozeMinutes {
                        Text("backup_alarm_before_snooze")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    /// 「7:00 のアラームを 7:15 までに止めなかったら…」を端末の時刻書式で組み立てる（#119）
    private var backupDescriptionText: String {
        guard let minutes = backupMinutes else { return "" }
        let components = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
        let times = BackupAlarmLogic.displayTimes(
            hour: components.hour ?? 7,
            minute: components.minute ?? 0,
            backupMinutes: minutes
        )
        let calendar = Calendar.current
        let now = Date()
        let originalDate = calendar.date(
            bySettingHour: times.originalHour,
            minute: times.originalMinute,
            second: 0,
            of: now
        ) ?? now
        let backupDate = calendar.date(
            bySettingHour: times.backupHour,
            minute: times.backupMinute,
            second: 0,
            of: now
        ) ?? now
        let style = Date.FormatStyle(date: .omitted, time: .shortened)
        return String(
            format: String(localized: "backup_alarm_description_fmt"),
            originalDate.formatted(style),
            backupDate.formatted(style)
        )
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            .foregroundStyle(Color.accentColor)
    }

    // MARK: - Trial Ring (#109 / #122)

    /// 本物の AlarmKit で1秒後に鳴らす。結果は行の中で短く表示する。
    private var testRingSection: some View {
        Section {
            HStack(spacing: 12) {
                Button {
                    scheduleTestRing(kind: .own)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.badge.waveform.fill")
                        Text("test_ring_title")
                        if isSchedulingTestRing {
                            ProgressView()
                        }
                    }
                }
                .buttonStyle(.borderless)
                .disabled(!scheduler.canScheduleTestRing || isSchedulingTestRing)
                .accessibilityIdentifier("addAlarm.testRing")

                Spacer()

                Button {
                    showingVolumeGuide = true
                } label: {
                    HStack(spacing: 2) {
                        Text("volume_guide_link")
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("addAlarm.volumeGuide")
            }

            if let testRingMessage {
                Text(testRingMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func scheduleTestRing(kind: TestRingKind) {
        guard !isSchedulingTestRing else { return }
        isSchedulingTestRing = true
        if kind == .backup {
            backupTestRingMessage = nil
        } else {
            testRingMessage = nil
        }

        Task {
            let fileName: String
            if kind == .backup {
                // 選択中の音を大きくした版で試す。無ければその場で生成（#119）
                fileName = await BackupLoudVariantService.ensureVariant(
                    for: selectedSound?.fileName ?? ""
                ) ?? BackupAlarmSound.fileName
            } else {
                fileName = selectedSound?.fileName ?? ""
            }

            let scheduled = await scheduler.scheduleTestRing(
                soundFileName: fileName,
                kind: kind
            )
            isSchedulingTestRing = false

            let message: String
            if scheduled {
                message = String(localized: "test_ring_ringing_now")
            } else {
                #if targetEnvironment(simulator)
                message = String(localized: "test_ring_simulator_unavailable")
                #else
                message = String(localized: "test_ring_failed")
                #endif
            }
            if kind == .backup {
                backupTestRingMessage = message
            } else {
                testRingMessage = message
            }

            // 行の中の短い結果は数秒で消す
            try? await Task.sleep(for: .seconds(4))
            if kind == .backup {
                if backupTestRingMessage == message { backupTestRingMessage = nil }
            } else if testRingMessage == message {
                testRingMessage = nil
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
            .accessibilityIdentifier("addAlarm.repeatRow")
        }
    }

    // MARK: - Snooze (#122: pull-down menu)

    private var snoozeOptions: [Int] {
        var options = [0, 1, 2, 5, 9, 10]
        if !options.contains(snoozeMinutes) {
            options.append(snoozeMinutes)
            options.sort()
        }
        return options
    }

    private var snoozeSection: some View {
        Section {
            HStack {
                Text("snooze")
                Spacer()
                Menu {
                    ForEach(snoozeOptions, id: \.self) { minutes in
                        Button(SnoozeDisplay.text(for: minutes)) {
                            snoozeMinutes = minutes
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(snoozeSummaryText)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("addAlarm.snoozeMenu")
            }
            .accessibilityIdentifier("addAlarm.snoozeRow")
        }
    }

    private var snoozeSummaryText: String {
        SnoozeDisplay.text(for: snoozeMinutes)
    }

    // MARK: - Label

    private var labelSection: some View {
        Section {
            HStack {
                Text("label")
                TextField("alarm_placeholder", text: $label)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("addAlarm.labelRow")
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
            let entry = AlarmSaveLogic.newEntry(
                hour: resolvedHour,
                minute: resolvedMinute,
                label: label,
                repeatWeekdays: Array(repeatWeekdays).sorted(),
                soundFileName: soundFileName,
                snoozeMinutes: snoozeMinutes,
                backupMinutes: backupMinutes
            )
            alarmStore.add(entry)
            AnalyticsService.shared.capture(
                .alarmCreated(hasCustomSound: hasCustomSound, isRepeating: isRepeating, snoozeMinutes: snoozeMinutes),
                properties: hoursUntilProperties(for: entry)
            )
            if let backupMinutes {
                AnalyticsService.shared.capture(.backupAlarmEnabled(minutes: backupMinutes))
            }
            savedEntry = entry
        case .edit(let existing):
            let updated = AlarmSaveLogic.updatedEntry(
                from: existing,
                hour: resolvedHour,
                minute: resolvedMinute,
                label: label,
                repeatWeekdays: Array(repeatWeekdays).sorted(),
                soundFileName: soundFileName,
                snoozeMinutes: snoozeMinutes,
                backupMinutes: backupMinutes
            )
            alarmStore.update(updated)
            AnalyticsService.shared.capture(
                .alarmEdited(hasCustomSound: hasCustomSound, isRepeating: isRepeating, snoozeMinutes: snoozeMinutes),
                properties: hoursUntilProperties(for: updated)
            )
            if existing.backupMinutes != updated.backupMinutes {
                if let newMinutes = updated.backupMinutes {
                    AnalyticsService.shared.capture(.backupAlarmEnabled(minutes: newMinutes))
                } else if let oldMinutes = existing.backupMinutes {
                    AnalyticsService.shared.capture(.backupAlarmDisabled(minutes: oldMinutes))
                }
            }
            savedEntry = updated
        }

        if BackupAlarmAccess.shouldGrantEarlyAccess(isEnabled: backupMinutes != nil) {
            AppGroup.backupEarlyAccessGranted = true
        }

        if backupMinutes != nil, let sourceFileName = selectedSound?.fileName, !sourceFileName.isEmpty {
            // 大きくした版の生成が終わってから最終アラームを登録する（#119）
            Task {
                _ = await BackupLoudVariantService.ensureVariant(for: sourceFileName)
                AlarmScheduler.shared.syncAlarms(alarmStore.alarms)
            }
        } else {
            AlarmScheduler.shared.syncAlarms(alarmStore.alarms)
        }

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

// MARK: - BackupAlarmInfoView

/// 寝過ごし防止の仕組みと先行公開の説明（#122）
struct BackupAlarmInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("backup_alarm_info_mechanism")
                    .font(.body)
                Text("backup_alarm_early_access_note")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(20)
            .navigationTitle(String(localized: "backup_alarm_info_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("close") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("backupInfo.root")
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
