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
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
    @State private var playlistID: UUID?
    @State private var fadeIn: PlaylistFadeIn
    @State private var playlistStore = PlaylistStore.shared
    @State private var showingPlaylistRequired = false
    /// 祝日は鳴らさない（#197）
    @State private var skipsHolidays: Bool
    @State private var holidayRingOverrides: Set<String>
    /// 日付を選んで休む（#197 画面作り直し）
    @State private var skipDates: Set<String>

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
            _playlistID = State(initialValue: entry.playlistID)
            _fadeIn = State(initialValue: entry.fadeIn)
            _skipsHolidays = State(initialValue: entry.skipsHolidays)
            _holidayRingOverrides = State(initialValue: Set(entry.holidayRingOverrides))
            _skipDates = State(initialValue: Set(entry.skipDates))
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
            _playlistID = State(initialValue: nil)
            _fadeIn = State(initialValue: .off)
            _skipsHolidays = State(initialValue: false)
            _holidayRingOverrides = State(initialValue: [])
            _skipDates = State(initialValue: [])
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // 3つのまとまり（#174 PR-2）:
                // 1. 時刻
                // 2. 繰り返し・ラベル・サウンド・やさしく鳴り始める・スヌーズ
                // 3. 今すぐ鳴らす（＋音が小さいときは）・寝過ごし防止
                timeSection
                Section {
                    repeatSection
                    labelSection
                    soundRow
                    fadeInRow
                    snoozeSection
                }
                Section {
                    testRingSection
                    backupAlarmRows
                } footer: {
                    backupAlarmFooter
                }
                if case .edit = mode {
                    deleteSection
                }
            }
            .accessibilityIdentifier("addAlarm.root")
            .warmListBackground()
            .onChange(of: repeatWeekdays) { _, weekdays in
                // 曜日を変えたら、合わない日付は黙って落とす（#197）
                let calendar = Calendar.current
                skipDates = skipDates.filter { key in
                    guard let date = AlarmSkipLogic.date(fromKey: key, calendar: calendar) else {
                        return false
                    }
                    return weekdays.contains(calendar.component(.weekday, from: date))
                }
            }
            .navigationTitle(isEditing ? String(localized: "edit_alarm") : String(localized: "add_alarm"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 長い言語（de の "Wecker hinzufügen" 等）でも省略記号で切れないよう、
                // タイトルだけ必要に応じて縮小する（#149）。
                ToolbarItem(placement: .principal) {
                    Text(isEditing ? String(localized: "edit_alarm") : String(localized: "add_alarm"))
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Text("cancel")
                    }
                    .tint(Color.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: {
                        Text("save")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.actionFillEnd)
                    .disabled(saveConfirmation != nil)
                    .accessibilityIdentifier("addAlarm.save")
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
                openUITestWaveformCropIfNeeded()
            }
            .sheet(isPresented: $showingVolumeGuide) {
                AlarmVolumeGuideView(source: .testRing)
            }
            .sheet(isPresented: $showingBackupInfo) {
                BackupAlarmInfoView()
                    .presentationDetents([.medium])
            }
            .alert("playlist_required_title", isPresented: $showingPlaylistRequired) {
                Button("ok", role: .cancel) {}
            } message: {
                Text("playlist_required_message")
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

    private var editingAlarmID: UUID? {
        if case .edit(let entry) = mode { return entry.id }
        return nil
    }

    /// UIテスト用: 同梱のプリセット音で波形クロップ画面を開く（DEBUGのみ・#149）。
    /// RTL 言語でも波形が左→右のままか screenshot で確認するために使う。
    private func openUITestWaveformCropIfNeeded() {
        #if DEBUG
        guard AppGroup.isUITestOpenWaveformCrop, pendingAudio == nil,
              let url = Bundle.main.url(forResource: "PresetMarimba", withExtension: "caf")
        else { return }
        pendingAudio = PendingAudioImport(url: url, name: String(localized: "preset_marimba"))
        #endif
    }

    // MARK: - Time (HIG: DatePicker)

    private var timeSection: some View {
        Section {
            // 時刻は「時 → 分」の並びを保つ（#149）。
            // RTL（アラビア語）だけ UIKit 版でホイールを LTR に固定し、
            // それ以外は従来の SwiftUI DatePicker のまま（影響範囲を RTL に限定）。
            if layoutDirection == .rightToLeft {
                TimeWheelPicker(date: $selectedTime)
                    .frame(maxWidth: .infinity)
                    .frame(height: 216)
            } else {
                DatePicker(
                    "time",
                    selection: $selectedTime,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
            }
        }
    }

    // MARK: - Sound / Fade (#160)

    private var soundRow: some View {
        NavigationLink {
            AlarmSoundChoiceView(
                playlistID: $playlistID,
                selectedSound: $selectedSound
            )
        } label: {
            AdaptiveDetailRow {
                VStack(alignment: .leading, spacing: 2) {
                    Text("sound")
                    if let playlist = playlistStore.playlist(id: playlistID) {
                        Text(playlistSummary(for: playlist))
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                    } else if playlistID != nil {
                        Text("playlist_missing")
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            } content: {
                HStack(spacing: 4) {
                    if playlistID == nil {
                        SoundIndicator(
                            isCustom: selectedSound != nil
                                && !(selectedSound?.isPreset ?? true),
                            size: 12
                        )
                    }
                    Text(soundRowValue)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                        .accessibilityIdentifier("addAlarm.soundName")
                }
            }
        }
        .accessibilityIdentifier("addAlarm.soundRow")
    }

    private var soundRowValue: String {
        if playlistID != nil {
            return playlistStore.playlist(id: playlistID)?.name
                ?? String(localized: "playlist_missing")
        }
        return selectedSound?.name ?? String(localized: "none")
    }

    private func playlistSummary(for playlist: Playlist) -> String {
        String(
            format: String(localized: "playlist_summary_fmt"),
            playOrderTitle(playlist.playOrder),
            playlist.trackCount
        )
    }

    private func playOrderTitle(_ order: PlaylistPlayOrder) -> String {
        switch order {
        case .inOrder: String(localized: "play_order_in_order")
        case .shuffle: String(localized: "play_order_shuffle")
        case .oneRandom: String(localized: "play_order_one_random")
        }
    }

    private var fadeInRow: some View {
        AdaptiveDetailRow {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text("fade_in")
                    if fadeIn != .off {
                        EarlyAccessBadge()
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Text("fade_in")
                    if fadeIn != .off {
                        EarlyAccessBadge()
                    }
                }
            }
        } content: {
            Picker("", selection: $fadeIn) {
                Text("fade_off").tag(PlaylistFadeIn.off)
                Text("fade_in_5").tag(PlaylistFadeIn.five)
                Text("fade_in_15").tag(PlaylistFadeIn.fifteen)
                Text("fade_in_30").tag(PlaylistFadeIn.thirty)
            }
            .labelsHidden()
            .accessibilityIdentifier("addAlarm.fadeIn")
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

    private var backupAlarmRows: some View {
        Group {
            AdaptiveDetailRow {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("backup_alarm_toggle")
                        HStack(spacing: 8) {
                            badge("PRO")
                            backupInfoButton
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Text("backup_alarm_toggle")
                        badge("PRO")
                        backupInfoButton
                    }
                }
            } content: {
                Toggle("", isOn: backupToggle)
                    .labelsHidden()
                    .tint(Brand.orange)
                    .accessibilityLabel(Text("backup_alarm_toggle"))
                    .accessibilityIdentifier("addAlarm.backupToggle")
                    // 使えない環境でも、既にオンならオフにはできる
                    .disabled(!isBackupAvailable && backupMinutes == nil)
            }

            if backupMinutes != nil {
                AdaptiveDetailRow {
                    Text("backup_alarm_minutes")
                } content: {
                    Picker("", selection: Binding(
                        get: { backupMinutes ?? BackupAlarmLogic.defaultMinutes },
                        set: { backupMinutes = $0 }
                    )) {
                        ForEach(BackupAlarmLogic.minuteOptions, id: \.self) { option in
                            Text(String(format: String(localized: "backup_alarm_minutes_fmt"), option))
                                .tag(option)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel(Text("backup_alarm_minutes"))
                    .accessibilityIdentifier("addAlarm.backupMinutes")
                }

                Button {
                    scheduleTestRing(kind: .backup)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "speaker.wave.3.fill")
                        Text("test_ring_backup_title")
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        if isSchedulingTestRing {
                            ProgressView()
                        }
                    }
                }
                .disabled(isSchedulingTestRing)
                .accessibilityIdentifier("addAlarm.backupTestRing")

                if let backupTestRingMessage {
                    Text(backupTestRingMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var backupAlarmFooter: some View {
        if let minutes = backupMinutes {
            VStack(alignment: .leading, spacing: 4) {
                Text(backupDescriptionText)
                if minutes <= snoozeMinutes {
                    Text("backup_alarm_before_snooze")
                        .foregroundStyle(Color.actionText)
                }
                if playlistID != nil {
                    Text("playlist_backup_note")
                        .foregroundStyle(Color.textSecondary)
                }
                if fadeIn != .off {
                    Text("fade_backup_note")
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .font(.footnote)
            .foregroundStyle(Color.textSecondary)
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
            .background(Capsule().fill(Color.actionFillEnd))
            .foregroundStyle(.white)
    }

    private var backupInfoButton: some View {
        Button {
            showingBackupInfo = true
        } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("backup_alarm_info_accessibility"))
        .accessibilityIdentifier("addAlarm.backupInfo")
    }

    // MARK: - Trial Ring (#109 / #122 / #150)

    /// 鳴らせない理由の恒常表示（許可が無い／拒否済みの間、行の下に出し続ける・#150）。
    private var testRingPermissionReason: TestRingReasonDisplay? {
        guard let reason = TestRingReasonLogic.permissionReason(
            permission: scheduler.testRingPermission
        ) else { return nil }
        return TestRingReasonLogic.display(for: reason)
    }

    /// 本物の AlarmKit で1秒後に鳴らす。鳴らせない理由はその場で、
    /// 一時的な結果（成功・登録失敗・シミュレータ）は行の中で短く表示する。
    private var testRingSection: some View {
        Group {
            Button {
                scheduleTestRing(kind: .own)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge.waveform.fill")
                    Text("test_ring_title")
                        .fixedSize(horizontal: false, vertical: true)
                    if isSchedulingTestRing {
                        ProgressView()
                    }
                }
            }
            .buttonStyle(.borderless)
            // 無効化したボタンだけを見せない（#150）: 押せるときは押させて理由を出す
            .disabled(isSchedulingTestRing)
            .accessibilityIdentifier("addAlarm.testRing")

            if let testRingPermissionReason {
                reasonRow(testRingPermissionReason, messageIdentifier: "addAlarm.testRingReason")
            } else if let testRingMessage {
                Text(testRingMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }

            // 「音が小さいときは」は押し間違い防止のため行の下の小さなリンク（#150）
            Button {
                showingVolumeGuide = true
            } label: {
                HStack(spacing: 2) {
                    Text("volume_guide_link")
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                }
                .font(.footnote)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.actionText)
            .accessibilityIdentifier("addAlarm.volumeGuide")
        }
    }

    /// 理由の行：短い理由 + 直し方（許可の問題なら「設定を開く」）。
    private func reasonRow(
        _ display: TestRingReasonDisplay,
        messageIdentifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: String.LocalizationValue(display.messageKey)))
                .font(.footnote)
                .foregroundStyle(Color.actionText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(messageIdentifier)
            if display.requestsPermission {
                Button("allow_alarms") {
                    Task {
                        _ = await scheduler.requestAuthorization()
                        scheduler.refreshTestRingPermission()
                    }
                }
                .font(.footnote.weight(.medium))
                .buttonStyle(.borderless)
                .accessibilityIdentifier("addAlarm.allowAlarms")
            }
            if display.showsOpenSettings {
                Button("open_settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .font(.footnote.weight(.medium))
                .buttonStyle(.borderless)
                .accessibilityIdentifier("addAlarm.openSettings")
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
            let draft = testRingDraftEntry()
            let fileName: String
            if kind == .backup {
                // プレイリストなら存在する1曲目の大きくした版で試す（本番と同じ・#169）
                let source = scheduler.backupSourceFileName(for: draft)
                fileName = await BackupLoudVariantService.ensureVariant(
                    for: source ?? ""
                ) ?? BackupAlarmSound.fileName
            } else {
                switch TestRingSoundLogic.primaryPlan(
                    playlistID: draft.playlistID,
                    selectedSoundFileName: draft.soundFileName,
                    fadeIn: draft.fadeIn,
                    entryID: draft.id
                ) {
                case .direct(let directFileName):
                    fileName = directFileName
                case .render(let input):
                    let resolution = await PlaylistRenderService.shared
                        .prepareTestRingSound(for: input)
                    fileName = resolution.fileName
                }
            }

            let result = await scheduler.scheduleTestRing(
                soundFileName: fileName,
                kind: kind,
                hasBackup: backupMinutes != nil
            )
            isSchedulingTestRing = false

            // 許可の理由は常時行の下に出ているため、本体の行では重複表示しない（#150）
            let permissionReasonShown =
                TestRingReasonLogic.permissionReason(permission: scheduler.testRingPermission) != nil
            let message: String? = switch result {
            case .scheduled:
                String(localized: "test_ring_ringing_now")
            case .failed(let reason):
                kind == .own && permissionReasonShown
                    ? nil
                    : String(
                        localized: String.LocalizationValue(
                            TestRingReasonLogic.display(for: reason).messageKey
                        )
                    )
            }
            guard let message else { return }

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

    /// 編集中（未保存）の内容を試し鳴らし用のエントリに写す（#169）。
    private func testRingDraftEntry() -> AlarmEntry {
        let components = Calendar.current.dateComponents(
            [.hour, .minute],
            from: selectedTime
        )
        return AlarmEntry(
            hour: components.hour ?? 7,
            minute: components.minute ?? 0,
            label: label,
            repeatWeekdays: Array(repeatWeekdays).sorted(),
            soundFileName: playlistID == nil ? (selectedSound?.fileName ?? "") : "",
            snoozeMinutes: snoozeMinutes,
            backupMinutes: backupMinutes,
            playlistID: playlistID,
            fadeIn: fadeIn
        )
    }

    // MARK: - Repeat

    private var repeatSection: some View {
        Group {
            NavigationLink {
                RepeatSelectionView(
                    selectedDays: $repeatWeekdays,
                    skipsHolidays: $skipsHolidays,
                    holidayRingOverrides: $holidayRingOverrides,
                    skipDates: $skipDates,
                    currentAlarmID: editingAlarmID
                )
            } label: {
                AdaptiveDetailRow {
                    Text("repeat")
                } content: {
                    Text(repeatSummary)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.leading)
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
        Group {
            AdaptiveDetailRow {
                Text("snooze")
            } content: {
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
                            .foregroundStyle(Color.textSecondary)
                    }
                    .foregroundStyle(Color.textSecondary)
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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    Text("label")
                    TextField("alarm_placeholder", text: $label)
                        .multilineTextAlignment(.leading)
                        .accessibilityIdentifier("addAlarm.labelRow")
                }
                .padding(.vertical, 2)
            } else {
                HStack {
                    Text("label")
                    TextField("alarm_placeholder", text: $label)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("addAlarm.labelRow")
                }
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
                        AlarmScheduler.shared.syncAlarms(alarmStore.alarms, trigger: .edit)
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
        // 試し聴きが残っていれば止める（#196）
        if SoundPreviewLogic.shouldStop(playingFileName: AudioPlayer.shared.playingFileName) {
            AudioPlayer.shared.stop()
        }

        let components = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
        let resolvedHour = components.hour ?? 7
        let resolvedMinute = components.minute ?? 0

        if playlistID != nil {
            guard let playlistID,
                  let playlist = playlistStore.playlist(id: playlistID),
                  !playlist.tracks.isEmpty else {
                showingPlaylistRequired = true
                return
            }
        }

        let soundFileName = playlistID == nil ? (selectedSound?.fileName ?? "") : ""
        let hasCustomSound = playlistID == nil
            && (selectedSound.map { !$0.isPreset } ?? false)
        let isRepeating = !repeatWeekdays.isEmpty

        // サウンド使用履歴を記録（新規作成時のデフォルト選択 + ピッカーの「最近使った」表示用）
        if playlistID == nil {
            SoundUsageHistory.recordUsage(soundFileName)
        }

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
                backupMinutes: backupMinutes,
                playlistID: playlistID,
                fadeIn: fadeIn,
                isEnabled: !AppGroup.isUITestDisableNewAlarm,
                skipsHolidays: skipsHolidays,
                holidayRingOverrides: Array(holidayRingOverrides).sorted(),
                skipDates: Array(skipDates).sorted()
            )
            alarmStore.add(entry)
            AnalyticsService.shared.capture(
                .alarmCreated(
                    hasCustomSound: hasCustomSound,
                    isRepeating: isRepeating,
                    snoozeMinutes: snoozeMinutes,
                    backupMinutes: backupMinutes ?? 0,
                    soundMode: AlarmSoundModeResolver.soundMode(for: entry),
                    fadeIn: fadeIn
                ),
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
                backupMinutes: backupMinutes,
                playlistID: playlistID,
                fadeIn: fadeIn,
                skipsHolidays: skipsHolidays,
                holidayRingOverrides: Array(holidayRingOverrides).sorted(),
                skipDates: Array(skipDates).sorted()
            )
            alarmStore.update(updated)
            AnalyticsService.shared.capture(
                .alarmEdited(
                    hasCustomSound: hasCustomSound,
                    isRepeating: isRepeating,
                    snoozeMinutes: snoozeMinutes,
                    backupMinutes: backupMinutes ?? 0,
                    wasEnabled: existing.isEnabled,
                    soundMode: AlarmSoundModeResolver.soundMode(for: updated),
                    fadeIn: fadeIn
                ),
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
        if PlaylistAccess.shouldGrantEarlyAccess(
            usedPlaylistFeatures: savedEntry.usesPlaylistFeatures
        ) {
            AppGroup.playlistEarlyAccessGranted = true
        }

        if backupMinutes != nil,
           playlistID == nil,
           let sourceFileName = selectedSound?.fileName,
           !sourceFileName.isEmpty {
            // 大きくした版の生成が終わってから最終アラームを登録する（#119）
            Task {
                _ = await BackupLoudVariantService.ensureVariant(for: sourceFileName)
                AlarmScheduler.shared.syncAlarms(
                    alarmStore.alarms,
                    editedEntryIDs: [savedEntry.id],
                    trigger: .edit
                )
            }
        } else {
            AlarmScheduler.shared.syncAlarms(
                alarmStore.alarms,
                editedEntryIDs: [savedEntry.id],
                trigger: .edit
            )
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
        RepeatSummaryLogic.text(
            weekdays: repeatWeekdays,
            skipsHolidays: skipsHolidays,
            skipDateCount: skipDates.count
        )
    }
}

// MARK: - BackupAlarmInfoView

/// 寝過ごし防止の仕組みと先行公開の説明（#122）
struct BackupAlarmInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("backup_alarm_info_mechanism")
                        .font(.body)
                    // もとの音が小さいほど大きく上げる（#134 の仕組みをそのまま説明）
                    Text("backup_alarm_info_louder")
                        .font(.body)
                    Text("backup_alarm_info_volume")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    Text("backup_alarm_early_access_note")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
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
    @Binding var skipsHolidays: Bool
    @Binding var holidayRingOverrides: Set<String>
    @Binding var skipDates: Set<String>
    /// 編集中のアラーム（「ほかのN本にも」から自分を除く）。
    let currentAlarmID: UUID?

    @State private var alarmStore = AlarmStore.shared
    @State private var scheduler = AlarmScheduler.shared
    @State private var showingSkipDates = false
    @State private var showingAllResults = false
    @State private var holidayOthersOffer: [UUID] = []
    @State private var showingHolidayOthersOffer = false

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
                                .foregroundStyle(Brand.orange)
                        }
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("repeat.day.\(day.id)")
            }

            // 曜日が空（1回きり）のときは、休みの設定を出さない（#197）。
            if !selectedDays.isEmpty {
                Section {
                    if AlarmSkipLogic.isJapanRegion() {
                        holidayToggle
                    }
                    skipDatesRow
                } header: {
                    Text("holiday_skip_section_title")
                }

                if !resultSections.isEmpty {
                    Section {
                        ForEach(resultSections) { yearSection in
                            if yearSection.year != currentYear {
                                Text(AlarmSkipFormat.year(yearSection.year))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.textSecondary)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            ForEach(yearSection.days) { day in
                                resultRow(day)
                            }
                        }
                        if hasMoreResults {
                            Button("skip_result_more") {
                                showingAllResults = true
                            }
                            .accessibilityIdentifier("skipResult.more")
                        }
                    } header: {
                        Text("skip_result_section_title")
                            .accessibilityIdentifier("skipResult.sectionTitle")
                    }
                }
            }
        }
        .warmListBackground()
        .navigationTitle(String(localized: "repeat"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Holiday

    private var holidayToggle: some View {
        Toggle("holiday_skip_toggle", isOn: Binding(
            get: { skipsHolidays },
            set: { enabled in
                let wasOn = skipsHolidays
                skipsHolidays = enabled
                AnalyticsService.shared.capture(.holidaySkipToggled(enabled: enabled))
                guard enabled, !wasOn else { return }
                let others = otherAlarmsSharingWeekday
                guard !others.isEmpty else { return }
                holidayOthersOffer = others.map(\.id)
                showingHolidayOthersOffer = true
            }
        ))
        .accessibilityIdentifier("addAlarm.holidaySkip")
        .alert(
            Text("holiday_skip_toggle"),
            isPresented: $showingHolidayOthersOffer
        ) {
            Button(String(
                format: String(localized: "holiday_apply_to_others_fmt"),
                holidayOthersOffer.count
            )) {
                applyHolidayToOthers()
            }
            Button("holiday_apply_only_this", role: .cancel) {}
        } message: {
            Text(String(
                format: String(localized: "holiday_others_message_fmt"),
                holidayOthersOffer.count
            ))
        }
    }

    /// 同じ曜日を含む、ほかのアラーム（#197）。
    private var otherAlarmsSharingWeekday: [AlarmEntry] {
        guard !selectedDays.isEmpty else { return [] }
        return alarmStore.alarms.filter { alarm in
            guard alarm.id != currentAlarmID, !alarm.repeatWeekdays.isEmpty else { return false }
            return !Set(alarm.repeatWeekdays).isDisjoint(with: selectedDays)
        }
    }

    private func applyHolidayToOthers() {
        for alarm in otherAlarmsSharingWeekday {
            var copy = alarm
            copy.skipsHolidays = true
            alarmStore.update(copy)
        }
        scheduler.syncAlarms(alarmStore.alarms, trigger: .edit)
    }

    // MARK: - Date skips

    private var skipDatesRow: some View {
        Button {
            showingSkipDates = true
        } label: {
            AdaptiveDetailRow {
                Text("skip_dates_title")
            } content: {
                Text(skipDatesCountText)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .accessibilityIdentifier("addAlarm.skipDates")
        .sheet(isPresented: $showingSkipDates) {
            AlarmSkipDatesSheet(skipDates: $skipDates)
        }
    }

    private var skipDatesCountText: String {
        skipDates.isEmpty
            ? String(localized: "skip_dates_none")
            : String(format: String(localized: "skip_dates_count_fmt"), skipDates.count)
    }

    // MARK: - Result list (#197 実機レビュー)

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var resultSections: [SkipResultYear] {
        resultSections(horizonDays: showingAllResults
            ? SkipResultLogic.extendedDays
            : SkipResultLogic.initialDays)
    }

    private var hasMoreResults: Bool {
        guard !showingAllResults else { return false }
        let initial = resultSections(horizonDays: SkipResultLogic.initialDays)
            .reduce(0) { $0 + $1.days.count }
        let extended = resultSections(horizonDays: SkipResultLogic.extendedDays)
            .reduce(0) { $0 + $1.days.count }
        return extended > initial
    }

    private func resultSections(horizonDays: Int) -> [SkipResultYear] {
        SkipResultLogic.sections(
            weekdays: selectedDays,
            skipsHolidays: skipsHolidays,
            skipDates: skipDates,
            holidayRingOverrides: holidayRingOverrides,
            isJapan: AlarmSkipLogic.isJapanRegion(),
            now: Date(),
            horizonDays: horizonDays
        )
    }

    @ViewBuilder
    private func resultRow(_ day: SkipResultDay) -> some View {
        switch day.kind {
        case .holiday(let name):
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(AlarmSkipFormat.day(day.date, includeYear: false)) \(name)")
                Spacer(minLength: 8)
                Button {
                    toggleHoliday(day.dateKey)
                } label: {
                    resultStatus(day.isSkipped)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("skipResult.toggle.\(day.dateKey)")
            }
        case .picked:
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(AlarmSkipFormat.day(day.date, includeYear: false)) \(String(localized: "skip_result_picked"))")
                Spacer(minLength: 8)
                resultStatus(true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("skipResult.picked.\(day.dateKey)")
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    skipDates.remove(day.dateKey)
                } label: {
                    Text("skip_result_remove")
                }
                .accessibilityIdentifier("skipResult.remove.\(day.dateKey)")
            }
        }
    }

    private func resultStatus(_ skipped: Bool) -> some View {
        Text(skipped ? "skip_result_off" : "skip_result_on")
            .foregroundStyle(skipped ? Color.textSecondary : Brand.orange)
    }

    private func toggleHoliday(_ dateKey: String) {
        if holidayRingOverrides.contains(dateKey) {
            holidayRingOverrides.remove(dateKey)
        } else {
            holidayRingOverrides.insert(dateKey)
        }
        AnalyticsService.shared.capture(.holidayRingOverride)
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

// MARK: - AdaptiveDetailRow (#174 PR-2)

/// 追加・編集画面の「項目名＋値」行。
/// AX サイズでは項目名の下に値を置き、単語途中の改行を避ける。
struct AdaptiveDetailRow<Title: View, Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let title: Title
    private let content: Content

    init(
        @ViewBuilder title: () -> Title,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title()
        self.content = content()
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                title
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)
        } else {
            HStack(alignment: .center, spacing: 12) {
                title
                Spacer(minLength: 12)
                content
            }
        }
    }
}
