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

/// 試し鳴らしの待ち状態（#297）。
/// 「試す」の準備中に「今すぐ鳴らす」まで止めないよう、種類ごとに持つ。
private enum TestRingPhase: Equatable {
    case idle
    /// 大きくした版を準備中（「試す」だけ）
    case preparing
    /// アラームを登録中
    case scheduling
}

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
    /// 画面を閉じる直前（#216: 戻った先で解放を出すため）
    var onClose: (() -> Void)?
    /// 保存したアラーム（#282: 一覧でその行に寄せるため）。
    /// 第2引数は光らせるか（新規作成、または時刻を変えた編集だけ true）。
    /// 第3引数は次に鳴るまでの1文を出すか（時刻・曜日・休み・オン/オフを変えた保存・#289）。
    var onSaved: ((AlarmEntry, Bool, Bool) -> Void)?
    /// 新規作成時に引き継いだ値（#206）
    private let carryOver: AlarmCarryOver
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
    /// 開いたときの保存項目（#308）。ここから変わったときだけ、閉じる前に確認する。
    @State private var initialDraft: AlarmDraft
    /// 変更を破棄するかの確認（#308）
    @State private var showingDiscardConfirmation = false

    /// オンボ指定の初期動作を1回だけ適用したか
    @State private var didApplyInitialImport = false
    /// 取り込み提示（#101 B: 追加画面に直接出す）
    @State private var isImporting = false
    @State private var pendingAudio: PendingAudioImport?
    @State private var showingVideoImport = false
    @State private var importErrorMessage: String?
    /// UIテスト用: 動画の切り取り画面を直接開くパス（#237）
    @State private var videoCropTestURL: URL?
    /// 取り込みで音量を上げた音のファイル名（#224）
    @State private var volumeBoostedFileName: String?

    /// 試しに鳴らす（#109）。待ち状態は「今すぐ鳴らす」と「試す」で分ける（#297）
    @State private var testRingPhase: TestRingPhase = .idle
    @State private var backupTestRingPhase: TestRingPhase = .idle
    @State private var backupVariantPreparation: LoudVariantPreparation?
    @State private var testRingMessage: String?
    @State private var backupTestRingMessage: String?

    /// 音量の案内（#121）・寝過ごし防止の説明（#122）
    @State private var showingVolumeGuide = false
    @State private var showingBackupInfo = false
    /// 時刻の候補を使った（#206）
    @State private var timeSuggestionUsed = false
    /// 履歴計測（#241）
    @State private var openedAt = Date()
    @State private var timeSuggestionIndex = -1
    @State private var didReportTimeSuggestion = false

    init(
        mode: AlarmDetailMode,
        initialImport: OnboardingSource? = nil,
        initialSound: AlarmSound? = nil,
        onClose: (() -> Void)? = nil,
        onSaved: ((AlarmEntry, Bool, Bool) -> Void)? = nil
    ) {
        self.mode = mode
        self.initialImport = initialImport
        self.onClose = onClose
        self.onSaved = onSaved

        let carryOver: AlarmCarryOver
        if case .edit = mode {
            carryOver = .defaults
        } else {
            carryOver = AlarmCarryOverLogic.carryOver(
                from: AlarmCarryOverStore.last,
                playlistExists: { PlaylistStore.shared.playlist(id: $0) != nil }
            )
        }
        self.carryOver = carryOver

        let startTime: Date
        let startLabel: String
        let startSound: AlarmSound?
        let startWeekdays: Set<Int>
        let startSnoozeMinutes: Int
        let startBackupMinutes: Int?
        let startPlaylistID: UUID?
        let startFadeIn: PlaylistFadeIn
        let startSkipsHolidays: Bool
        let startHolidayRingOverrides: Set<String>
        let startSkipDates: Set<String>

        if case .edit(let entry) = mode {
            var components = DateComponents()
            components.hour = entry.hour
            components.minute = entry.minute
            startTime = Calendar.current.date(from: components) ?? Date()
            startLabel = entry.label
            startWeekdays = Set(entry.repeatWeekdays)
            startSound = SoundStore.shared.sounds.first { $0.fileName == entry.soundFileName }
            startSnoozeMinutes = entry.snoozeMinutes
            startBackupMinutes = entry.backupMinutes
            startPlaylistID = entry.playlistID
            startFadeIn = entry.fadeIn
            startSkipsHolidays = entry.skipsHolidays
            startHolidayRingOverrides = Set(entry.holidayRingOverrides)
            startSkipDates = Set(entry.skipDates)
        } else {
            // UIテスト・録画用: 追加画面の初期時刻を固定する（DEBUGのみ・#282）
            let presetTime = AppGroup.uitestAddAlarmTime
                .flatMap { Calendar.current.date(from: $0) }
            startTime = presetTime ?? Date()
            startLabel = String(localized: "alarm_placeholder")
            // 前回保存時に使った音をデフォルト選択（存在しない/削除済みなら nil）
            let lastUsedSound = SoundUsageHistory.lastUsedFileName.flatMap { fileName in
                SoundStore.shared.sounds.first { $0.fileName == fileName }
            }
            startSound = initialSound ?? lastUsedSound
            startWeekdays = []
            startSnoozeMinutes = carryOver.snoozeMinutes
            startBackupMinutes = nil
            startPlaylistID = carryOver.playlistID
            startFadeIn = carryOver.fadeIn
            startSkipsHolidays = false
            startHolidayRingOverrides = []
            startSkipDates = []
        }

        _selectedTime = State(initialValue: startTime)
        _label = State(initialValue: startLabel)
        _selectedSound = State(initialValue: startSound)
        _repeatWeekdays = State(initialValue: startWeekdays)
        _snoozeMinutes = State(initialValue: startSnoozeMinutes)
        _backupMinutes = State(initialValue: startBackupMinutes)
        _playlistID = State(initialValue: startPlaylistID)
        _fadeIn = State(initialValue: startFadeIn)
        _skipsHolidays = State(initialValue: startSkipsHolidays)
        _holidayRingOverrides = State(initialValue: startHolidayRingOverrides)
        _skipDates = State(initialValue: startSkipDates)

        let calendar = Calendar.current
        _initialDraft = State(initialValue: AlarmDraft(
            hour: calendar.component(.hour, from: startTime),
            minute: calendar.component(.minute, from: startTime),
            label: startLabel,
            repeatWeekdays: startWeekdays.sorted(),
            soundFileName: AlarmDraftLogic.soundFileName(
                playlistID: startPlaylistID,
                selectedSoundFileName: startSound?.fileName
            ),
            snoozeMinutes: startSnoozeMinutes,
            backupMinutes: startBackupMinutes,
            playlistID: startPlaylistID,
            fadeIn: startFadeIn,
            skipsHolidays: startSkipsHolidays,
            holidayRingOverrides: startHolidayRingOverrides.sorted(),
            skipDates: startSkipDates.sorted()
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                // #211: よく触るものを上に、たまに触るものは「その他」へ
                // 1. 時刻
                // 2. サウンド・繰り返し・寝過ごし防止・今すぐ鳴らす・その他
                timeSection
                Section {
                    soundRow
                    if showsVolumeBoostedNotice {
                        volumeNoticeRow
                    }
                    repeatSection
                    backupAlarmRows
                    testRingSection
                    moreRow
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
            // 大きくした版を先に作り始める（#297）。
            // 「試す」を押した時点でできていれば、待たずに鳴る。
            .onChange(of: backupMinutes) { _, minutes in
                if minutes != nil { prepareBackupVariantInBackground() }
            }
            .onChange(of: selectedSound) { _, _ in
                prepareBackupVariantInBackground()
            }
            .onChange(of: playlistID) { _, _ in
                prepareBackupVariantInBackground()
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
                    Button {
                        requestClose()
                    } label: {
                        Text("cancel")
                    }
                    .tint(Color.primary)
                    .accessibilityIdentifier("addAlarm.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: {
                        Text("save")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.actionFillEnd)
                    .accessibilityIdentifier("addAlarm.save")
                }
            }
            .soundImport(
                selectedSound: $selectedSound,
                isImporting: $isImporting,
                pendingAudio: $pendingAudio,
                showingVideoImport: $showingVideoImport,
                errorMessage: $importErrorMessage,
                volumeBoostedFileName: $volumeBoostedFileName,
                initialVideoURL: videoCropTestURL
            )
            .task {
                scheduler.refreshTestRingPermission()
                // 追加画面のシート提示完了後に取り込みを開く（約0.35秒待つ）
                try? await Task.sleep(for: .milliseconds(500))
                applyInitialImportOnce()
                #if DEBUG
                // UIテスト用: -uitestVideoCropPath <動画> で動画の切り取り画面を開く（#237）
                if videoCropTestURL == nil,
                   let path = UserDefaults.standard.string(forKey: "uitestVideoCropPath"),
                   FileManager.default.fileExists(atPath: path) {
                    videoCropTestURL = URL(fileURLWithPath: path)
                    showingVideoImport = true
                }
                #endif
                reportTimeSuggestionsIfNeeded()
                // 親シートの提示が終わってから開く（#149）
                openUITestWaveformCropIfNeeded()
            }
            .onAppear {
                scheduler.refreshTestRingPermission()
            }
            .sheet(isPresented: $showingVolumeGuide) {
                AlarmVolumeGuideView(source: .testRing)
            }
            .sheet(isPresented: $showingBackupInfo) {
                BackupAlarmInfoView(
                    hour: selectedHour,
                    minute: selectedMinute,
                    backupMinutes: backupMinutes ?? BackupAlarmLogic.defaultMinutes,
                    showsPlaylistNote: backupMinutes != nil && playlistID != nil,
                    showsFadeNote: backupMinutes != nil && fadeIn != .off
                )
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
            // 下に払う操作（#308）。UIKit のデリゲートで拾い、変更があるときだけ確認を出す。
            .interactiveDismissDisabled(hasChanges)
            .background {
                InteractiveDismissAttemptReader(hasChanges: hasChanges) {
                    showingDiscardConfirmation = true
                }
                .frame(width: 0, height: 0)
            }
            // 確認は2つだけ。タイトル・説明文は付けない（iOS のカレンダー・リマインダーと同じ）。
            .confirmationDialog(
                "",
                isPresented: $showingDiscardConfirmation,
                titleVisibility: .hidden
            ) {
                Button("discard_changes", role: .destructive) {
                    close()
                }
                Button("keep_editing", role: .cancel) {}
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

    /// いま画面に出ている、保存される項目（#308）。
    private var currentDraft: AlarmDraft {
        AlarmDraft(
            hour: selectedHour,
            minute: selectedMinute,
            label: label,
            repeatWeekdays: repeatWeekdays.sorted(),
            soundFileName: AlarmDraftLogic.soundFileName(
                playlistID: playlistID,
                selectedSoundFileName: selectedSound?.fileName
            ),
            snoozeMinutes: snoozeMinutes,
            backupMinutes: backupMinutes,
            playlistID: playlistID,
            fadeIn: fadeIn,
            skipsHolidays: skipsHolidays,
            holidayRingOverrides: holidayRingOverrides.sorted(),
            skipDates: skipDates.sorted()
        )
    }

    /// 開いたときから、保存される項目が1つでも変わっているか（#308）。
    private var hasChanges: Bool {
        AlarmDraftLogic.hasChanges(initial: initialDraft, current: currentDraft)
    }

    /// 「キャンセル」と下に払う操作の共通の入り口（#308）。
    /// 変更があるときだけ確認を出し、なければ今まで通り閉じる。
    private func requestClose() {
        if hasChanges {
            showingDiscardConfirmation = true
        } else {
            close()
        }
    }

    private func close() {
        onClose?()
        dismiss()
    }

    private var editingAlarmID: UUID? {
        if case .edit(let entry) = mode { return entry.id }
        return nil
    }

    /// UIテスト用: 同梱のプリセット音で波形クロップ画面を開く（DEBUGのみ・#149）。
    /// RTL 言語でも波形が左→右のままか screenshot で確認するために使う。
    private func openUITestWaveformCropIfNeeded() {
        #if DEBUG
        guard AppGroup.isUITestOpenWaveformCrop, pendingAudio == nil else { return }
        // UIテスト用: ミュージックライブラリから選んだあとの流れ（#245）
        if AppGroup.isUITestMusicCrop {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("MusicCrop-\(UUID().uuidString).caf")
            try? SilentTestAudioFactory.makeToneFile(at: url)
            pendingAudio = PendingAudioImport(
                url: url,
                name: "Test Song",
                source: .musicLibrary
            )
            return
        }
        // #303: 選択範囲が下段の窓（最大60秒）より広い状態を再現する
        if AppGroup.isUITestLongCrop {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("LongCrop-\(UUID().uuidString).caf")
            try? SilentTestAudioFactory.makeToneFile(at: url, seconds: 120)
            pendingAudio = PendingAudioImport(url: url, name: "Long tone")
            return
        }
        // ストアのスクショ用: -uitestCropPath <音声ファイル> -uitestCropName <表示名> で差し替える。
        if AppGroup.isUITestSilentCrop {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("SilentCrop-\(UUID().uuidString).caf")
            try? SilentTestAudioFactory.makeSilentFile(at: url)
            pendingAudio = PendingAudioImport(url: url, name: "Silent")
            return
        }
        if AppGroup.isUITestPartialSilentCrop {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("PartialSilentCrop-\(UUID().uuidString).caf")
            try? SilentTestAudioFactory.makePartialSilentFile(at: url)
            pendingAudio = PendingAudioImport(url: url, name: "Partial silent")
            return
        }
        if AppGroup.isUITestQuietCrop,
           let source = Bundle.main.url(forResource: "PresetMarimba", withExtension: "caf") {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("QuietCrop-\(UUID().uuidString).caf")
            try? FileManager.default.copyItem(at: source, to: url)
            try? AudioConverter.applyGainSync(fileURL: url, gainDb: -20)
            pendingAudio = PendingAudioImport(url: url, name: "Quiet")
            return
        }
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: "uitestCropPath"),
           FileManager.default.fileExists(atPath: path) {
            pendingAudio = PendingAudioImport(
                url: URL(fileURLWithPath: path),
                name: defaults.string(forKey: "uitestCropName") ?? "Morning"
            )
            return
        }
        guard let source = Bundle.main.url(forResource: "PresetMarimba", withExtension: "caf")
        else { return }
        // AudioCropView は一時ファイルを閉じるときに削除する（#245）。
        // バンドルのプリセットを直接渡すとバンドルから消えてしまうため、必ずコピーを渡す。
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PresetCrop-\(UUID().uuidString).caf")
        guard (try? FileManager.default.copyItem(at: source, to: url)) != nil else { return }
        pendingAudio = PendingAudioImport(url: url, name: String(localized: "preset_marimba"))
        #endif
    }

    // MARK: - Time (HIG: DatePicker)

    private var timeSuggestions: [AlarmTimeSuggestion] {
        guard !isEditing else { return [] }
        return AlarmTimeSuggestionLogic.suggestions(
            entries: alarmStore.alarms,
            after: Date()
        )
    }

    private func applyTimeSuggestion(_ suggestion: AlarmTimeSuggestion) {
        var components = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: selectedTime
        )
        components.hour = suggestion.hour
        components.minute = suggestion.minute
        guard let date = Calendar.current.date(from: components) else { return }
        selectedTime = date
        timeSuggestionUsed = true
        timeSuggestionIndex = timeSuggestions.firstIndex(of: suggestion) ?? -1
    }

    /// 候補を出したことを1画面1回だけ記録する（#241）。
    private func reportTimeSuggestionsIfNeeded() {
        guard !isEditing, !didReportTimeSuggestion else { return }
        let suggestions = timeSuggestions
        guard !suggestions.isEmpty else { return }
        didReportTimeSuggestion = true
        AnalyticsService.shared.capture(.timeSuggestionShown(
            suggestions: suggestions.map(\.label).joined(separator: ",")
        ))
    }

    private var timeSection: some View {
        Section {
            if !timeSuggestions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(timeSuggestions) { suggestion in
                        Button(suggestion.label) {
                            applyTimeSuggestion(suggestion)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier(
                            "addAlarm.timeSuggestion.\(suggestion.hour)_\(suggestion.minute)"
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
            }

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
                .accessibilityIdentifier("addAlarm.timePicker")
            }
        }
    }

    // MARK: - Sound / Fade (#160)

    /// 1行は、いま選んでいる音が「大きくした音」のときだけ出す（#224 レビュー）。
    private var showsVolumeBoostedNotice: Bool {
        guard let volumeBoostedFileName else { return false }
        return playlistID == nil && selectedSound?.fileName == volumeBoostedFileName
    }

    private var volumeNoticeRow: some View {
        Label("volume_notice", systemImage: "speaker.wave.3")
            .font(.footnote)
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("addAlarm.volumeNotice")
    }

    private var soundRow: some View {
        NavigationLink {
            AlarmSoundChoiceView(
                playlistID: $playlistID,
                selectedSound: $selectedSound,
                volumeBoostedFileName: $volumeBoostedFileName
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
            playlist.trackCount,
            playOrderTitle(playlist.playOrder)
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
            Text("fade_in")
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

    // MARK: - More (#211)

    /// スヌーズ・ラベル・やさしく鳴り始めるをまとめた1行。要約は変えたものを先頭に2つまで。
    private var moreRow: some View {
        NavigationLink {
            moreScreen
        } label: {
            AdaptiveDetailRow {
                Text("more")
            } content: {
                Text(moreSummaryText)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: moreAccessibilityText))
        .accessibilityIdentifier("addAlarm.moreRow")
    }

    private var moreScreen: some View {
        Form {
            Section {
                snoozeSection
                labelSection
                fadeInRow
            }
        }
        .accessibilityIdentifier("addAlarm.more.root")
        .warmListBackground()
        .navigationTitle(String(localized: "more"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            AnalyticsService.shared.capture(.alarmEditorMoreOpened)
        }
    }

    private var fadeInSummaryValue: String {
        switch fadeIn {
        case .off: String(localized: "fade_off")
        case .five: String(localized: "fade_in_5")
        case .fifteen: String(localized: "fade_in_15")
        case .thirty: String(localized: "fade_in_30")
        }
    }

    private var moreSummary: AlarmEditorMoreSummary.Result {
        AlarmEditorMoreSummary.make(
            label: label,
            defaultLabel: String(localized: "alarm_placeholder"),
            snoozeMinutes: snoozeMinutes,
            snoozeValue: SnoozeDisplay.text(for: snoozeMinutes),
            fadeIn: fadeIn,
            fadeValue: fadeInSummaryValue,
            strings: AlarmEditorMoreSummary.Strings(
                labelFormat: String(localized: "more_label_fmt"),
                noLabel: String(localized: "more_no_label"),
                snoozeTitle: String(localized: "snooze"),
                fadeTitle: String(localized: "fade_in"),
                separator: String(localized: "more_separator"),
                accessibilityFormat: String(localized: "more_accessibility_fmt"),
                moreTitle: String(localized: "more")
            )
        )
    }

    private var moreSummaryText: String {
        moreSummary.displayItems.joined(separator: String(localized: "more_separator"))
    }

    private var moreAccessibilityText: String {
        moreSummary.accessibilityText
    }

    // MARK: - Oversleep guard (#110 / #122)

    private var isBackupAvailable: Bool {
        BackupAlarmAccess.isAvailable(
            isPro: Entitlements.shared.isPro,
            earlyAccessGranted: AppGroup.backupEarlyAccessGranted
        )
    }

    /// 保存済みの値が選択肢に無い場合（例: 旧データの5分）も表示できるようにする。
    private var backupMinuteOptions: [Int] {
        var options = BackupAlarmLogic.minuteOptions
        if let minutes = backupMinutes, !options.contains(minutes) {
            options.append(minutes)
            options.sort()
        }
        return options
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
                HStack(spacing: 8) {
                    Text("backup_alarm_toggle")
                    backupInfoButton
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

            if let minutes = backupMinutes {
                // #290: 条件は行の名前「寝過ごし防止」に任せ、鳴る時刻の1文だけにする。
                // 「試す」は同じ行の右にまとめ、行を増やさない。
                AdaptiveDetailRow {
                    Text(backupSummaryText(minutes: minutes))
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("addAlarm.backupDescription")
                } content: {
                    Button {
                        scheduleTestRing(kind: .backup)
                    } label: {
                        HStack(spacing: 4) {
                            if backupTestRingPhase == .preparing {
                                // まだできていないときは、進み具合の円を出す（#297）
                                ProgressView(value: backupVariantPreparation?.progress ?? 0)
                                    .progressViewStyle(.circular)
                                    .controlSize(.mini)
                                    .accessibilityIdentifier("addAlarm.backupTestRingProgress")
                            } else if backupTestRingPhase == .scheduling {
                                ProgressView()
                            } else {
                                Image(systemName: "play.fill")
                                    .font(.caption2)
                            }
                            Text("backup_try")
                        }
                        .font(.footnote.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.actionText)
                    .disabled(backupTestRingPhase != .idle)
                    .accessibilityIdentifier("addAlarm.backupTestRing")
                }

                // 設定が食い違うときだけ出す、直すべき警告（#211 レビュー）
                if let minutes = backupMinutes, minutes <= snoozeMinutes {
                    Text("backup_alarm_before_snooze")
                        .font(.footnote)
                        .foregroundStyle(Color.actionText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("addAlarm.backupBeforeSnooze")
                }

                AdaptiveDetailRow {
                    Text("backup_alarm_minutes")
                } content: {
                    Picker("", selection: Binding(
                        get: { backupMinutes ?? BackupAlarmLogic.defaultMinutes },
                        set: { backupMinutes = $0 }
                    )) {
                        ForEach(backupMinuteOptions, id: \.self) { option in
                            Text(String(format: String(localized: "backup_alarm_minutes_fmt"), option))
                                .tag(option)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel(Text("backup_alarm_minutes"))
                    .accessibilityIdentifier("addAlarm.backupMinutes")
                }

                if let backupTestRingMessage {
                    Text(backupTestRingMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    private var selectedHour: Int {
        Calendar.current.component(.hour, from: selectedTime)
    }

    private var selectedMinute: Int {
        Calendar.current.component(.minute, from: selectedTime)
    }

    private func backupSummaryText(minutes: Int) -> String {
        backupAlarmSummaryText(
            hour: selectedHour,
            minute: selectedMinute,
            backupMinutes: minutes
        )
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
                    if testRingPhase == .scheduling {
                        ProgressView()
                    }
                }
            }
            .buttonStyle(.borderless)
            // 無効化したボタンだけを見せない（#150）: 押せるときは押させて理由を出す
            .disabled(testRingPhase != .idle)
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

    /// 理由の行：直し方が設定のときは、短い状態の一言 +「設定を開く」にする（#290）。
    /// 理由そのものは VoiceOver のラベルに残す。
    private func reasonRow(
        _ display: TestRingReasonDisplay,
        messageIdentifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if display.showsOpenSettings {
                AdaptiveDetailRow {
                    Label("test_ring_status_alarms_off", systemImage: "bell.slash.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .accessibilityLabel(Text("test_ring_status_alarms_off"))
                        .accessibilityIdentifier("addAlarm.testRingStatus")
                } content: {
                    Button("open_settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .font(.footnote.weight(.medium))
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.actionText)
                    .accessibilityIdentifier("addAlarm.openSettings")
                    .accessibilityLabel(Text(verbatim: String(
                        localized: String.LocalizationValue(display.messageKey)
                    )))
                    .accessibilityHint(Text("open_settings"))
                }
            } else {
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
            }
        }
    }

    private func scheduleTestRing(kind: TestRingKind) {
        // 待ち状態は種類ごとに分ける（#297）。
        // 寝過ごし防止の準備中でも「今すぐ鳴らす」は押せる。
        switch kind {
        case .own:
            guard testRingPhase == .idle else { return }
            testRingPhase = .scheduling
            testRingMessage = nil
        case .backup:
            guard backupTestRingPhase == .idle else { return }
            backupTestRingPhase = .scheduling
            backupTestRingMessage = nil
        }

        Task {
            let draft = testRingDraftEntry()
            let fileName: String
            if kind == .backup {
                // プレイリストなら存在する1曲目の大きくした版で試す（本番と同じ・#169）
                let source = scheduler.backupSourceFileName(for: draft) ?? ""
                // まだできていないときだけ、生成の進み具合を出す（#297）
                if !source.isEmpty,
                   BackupLoudVariantService.existingVariantFileName(for: source) == nil {
                    let preparation = BackupLoudVariantService.preparation(for: source)
                        ?? BackupLoudVariantService.prepareInBackground(for: source)
                    backupVariantPreparation = preparation
                    if preparation != nil {
                        backupTestRingPhase = .preparing
                    }
                }
                fileName = await BackupLoudVariantService.ensureVariant(
                    for: source
                ) ?? BackupAlarmSound.fileName
                backupVariantPreparation = nil
                backupTestRingPhase = .scheduling
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
            switch kind {
            case .own:
                testRingPhase = .idle
            case .backup:
                backupTestRingPhase = .idle
                backupVariantPreparation = nil
            }

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

    /// 大きくした版を裏で作り始める（#297）。
    /// 寝過ごし防止をオンにしたとき・音を変えたとき・保存したときに呼ぶ。
    private func prepareBackupVariantInBackground() {
        guard let source = BackupLoudVariantService.sourceToPrepare(
            backupMinutes: backupMinutes,
            resolvedSourceFileName: scheduler.backupSourceFileName(for: testRingDraftEntry())
        ) else { return }
        BackupLoudVariantService.prepareInBackground(for: source)
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
                    }
                    .foregroundStyle(Color.actionText)
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

    private func save() {
        let listBeforeSave = alarmStore.alarms
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
                    fadeIn: fadeIn,
                    timeSuggestionUsed: timeSuggestionUsed,
                    carriedOver: AlarmCarryOverLogic.carriedOver(
                        initial: carryOver,
                        snoozeMinutes: snoozeMinutes,
                        playlistID: playlistID,
                        fadeIn: fadeIn
                    ),
                    context: makeHistoryContext(
                        entry: entry,
                        list: listBeforeSave,
                        suggestionIndex: timeSuggestionIndex,
                        secondsToSave: max(0, Int(Date().timeIntervalSince(openedAt))),
                        prevAlarmTime: nil
                    )
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
                    fadeIn: fadeIn,
                    context: makeHistoryContext(
                        entry: updated,
                        list: listBeforeSave,
                        suggestionIndex: nil,
                        secondsToSave: nil,
                        prevAlarmTime: existing.timeString
                    )
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

        // 次に新規作成するときの初期値（#206）
        AlarmCarryOverStore.save(from: savedEntry)

        // 光らせるのは新規作成と、時刻を変えた編集だけ（#282）。
        // 次に鳴るまでの1文は、時刻・曜日・休み・オン/オフを変えた保存でも出す（#289）。
        let previous: AlarmEntry?
        if case .edit(let existing) = mode {
            previous = existing
        } else {
            previous = nil
        }
        let shouldSpotlight: Bool
        if let previous {
            shouldSpotlight = AlarmSpotlightLogic.shouldSpotlight(
                isNew: false,
                oldHour: previous.hour,
                oldMinute: previous.minute,
                newHour: savedEntry.hour,
                newMinute: savedEntry.minute
            )
        } else {
            shouldSpotlight = true
        }
        let shouldAnnounce = NextRingAnnouncement.shouldAnnounce(
            isNew: previous == nil,
            previous: previous,
            updated: savedEntry
        )

        // 保存した時点で一覧側へ知らせ、シートが閉じるまでは行を出さない（#282 レビュー）
        onSaved?(savedEntry, shouldSpotlight, shouldAnnounce)

        if BackupAlarmAccess.shouldGrantEarlyAccess(isEnabled: backupMinutes != nil) {
            AppGroup.backupEarlyAccessGranted = true
        }
        if PlaylistAccess.shouldGrantEarlyAccess(
            usedPlaylistFeatures: savedEntry.usesPlaylistFeatures
        ) {
            AppGroup.playlistEarlyAccessGranted = true
        }

        // 保存した時点で、大きくした版を裏で作り始める（#297）
        if let source = BackupLoudVariantService.sourceToPrepare(
            backupMinutes: backupMinutes,
            resolvedSourceFileName: scheduler.backupSourceFileName(for: savedEntry)
        ) {
            BackupLoudVariantService.prepareInBackground(for: source)
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

        // 保存後のフィードバックは一覧の上に出す（#289）。
        // シートはすぐ閉じ、一覧のスクロールが止まって光るときに1文を出す。
        onClose?()
        dismiss()
    }

    /// アラーム履歴の共通プロパティを作る（#241）。
    private func makeHistoryContext(
        entry: AlarmEntry,
        list: [AlarmEntry],
        suggestionIndex: Int?,
        secondsToSave: Int?,
        prevAlarmTime: String?
    ) -> AlarmEventContext {
        if case .add = mode {
            AlarmUIDStore.recordCreation(entry.id)
        }
        var context = AlarmHistoryLogic.context(for: entry)
        context.list = AlarmHistoryLogic.listSnapshot(list)
        context.suggestionIndex = suggestionIndex
        context.secondsToSave = secondsToSave
        context.prevAlarmTime = prevAlarmTime
        return context
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

// MARK: - Backup alarm copy

/// 寝過ごし防止の1文（#290）。条件は書かず、鳴る時刻だけを端末の書式で出す。
private func backupAlarmSummaryText(
    hour: Int,
    minute: Int,
    backupMinutes: Int
) -> String {
    let times = BackupAlarmLogic.displayTimes(
        hour: hour,
        minute: minute,
        backupMinutes: backupMinutes
    )
    let backupTime = AlarmTimeFormat.display(
        hour: times.backupHour,
        minute: times.backupMinute
    )
    return String(
        format: String(localized: "backup_alarm_summary_fmt"),
        backupTime
    )
}

// MARK: - BackupAlarmInfoView

private struct BackupInfoHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 寝過ごし防止の仕組みと先行公開の説明（#122）
struct BackupAlarmInfoView: View {
    @Environment(\.dismiss) private var dismiss
    var hour: Int
    var minute: Int
    var backupMinutes: Int
    /// 今の設定で当てはまる補足だけを出す（#211: 画面の長い説明をこちらへ）
    var showsPlaylistNote = false
    var showsFadeNote = false
    @State private var contentHeight: CGFloat = 0

    /// 大きい文字では閉じるボタンと横に並べず、タイトルに幅を全部使わせる
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                title
                Spacer(minLength: 12)
                closeButton
            }
            VStack(alignment: .leading, spacing: 8) {
                title
                HStack {
                    Spacer()
                    closeButton
                }
            }
        }
    }

    private var title: some View {
        Text("backup_alarm_info_title")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }

    private var closeButton: some View {
        Button("close") { dismiss() }
            .font(.body.weight(.medium))
            .foregroundStyle(Color.actionText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 12) {
                // #290: 図はやめ、行と同じ1文 + 音量の注意だけにする
                Text(backupAlarmSummaryText(
                    hour: hour,
                    minute: minute,
                    backupMinutes: backupMinutes
                ))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                Text("backup_alarm_info_volume")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if showsPlaylistNote {
                    Text("playlist_backup_note")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if showsFadeNote {
                    Text("fade_backup_note")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: BackupInfoHeightKey.self,
                    value: proxy.size.height
                )
            }
        }
        .onPreferenceChange(BackupInfoHeightKey.self) { height in
            contentHeight = height
        }
        // 中身の高さに合わせ、medium の空白を残さない（#290）
        .presentationDetents([.height(max(180, contentHeight))])
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
                    } footer: {
                        if skipsHolidays {
                            Text("skip_result_footer")
                                .accessibilityIdentifier("skipResult.footer")
                        }
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

// MARK: - AlarmEditorMoreSummary (#211)

/// 「その他」1行の要約（#211・単体テスト対象）。
/// 変えたものを先頭に2つまで。何も変えていなければスヌーズの初期値を1つ。
enum AlarmEditorMoreSummary {

    struct Strings {
        let labelFormat: String
        let noLabel: String
        let snoozeTitle: String
        let fadeTitle: String
        let separator: String
        let accessibilityFormat: String
        let moreTitle: String
    }

    struct Result: Equatable {
        let displayItems: [String]
        let accessibilityText: String
    }

    static func make(
        label: String,
        defaultLabel: String,
        snoozeMinutes: Int,
        snoozeValue: String,
        fadeIn: PlaylistFadeIn,
        fadeValue: String,
        strings: Strings
    ) -> Result {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCustomLabel = !trimmedLabel.isEmpty && trimmedLabel != defaultLabel
        let labelItem = hasCustomLabel
            ? String(format: strings.labelFormat, trimmedLabel)
            : strings.noLabel
        let snoozeItem = "\(strings.snoozeTitle) \(snoozeValue)"
        let fadeItem = "\(strings.fadeTitle) \(fadeValue)"

        var changed: [String] = []
        if hasCustomLabel {
            changed.append(labelItem)
        }
        if snoozeMinutes != AlarmCarryOver.defaults.snoozeMinutes {
            changed.append(snoozeItem)
        }
        if fadeIn != .off {
            changed.append(fadeItem)
        }

        let display: [String]
        if changed.isEmpty {
            display = [snoozeItem]
        } else if changed.count == 1, changed[0] != snoozeItem {
            display = [changed[0], snoozeItem]
        } else {
            display = changed
        }

        // VoiceOver は「その他、スヌーズ 9分・ラベルなし」の順で読む（#211 レビュー）。
        var accessibilityItems = [snoozeItem, labelItem]
        if fadeIn != .off {
            accessibilityItems.append(fadeItem)
        }
        let accessibilityText = String(
            format: strings.accessibilityFormat,
            strings.moreTitle,
            accessibilityItems.joined(separator: strings.separator)
        )

        return Result(
            displayItems: Array(display.prefix(2)),
            accessibilityText: accessibilityText
        )
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
                .accessibilityIdentifier("toast.text")
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

// MARK: - Interactive dismiss attempt (#308)

/// 下に払おうとしたことを UIKit から受け取る（SwiftUI だけでは取れない）。
/// シートの presentationController に自分をデリゲートとして付け、
/// 変更があるときは閉じずに `onAttempt` を呼ぶ。
private struct InteractiveDismissAttemptReader: UIViewControllerRepresentable {
    let hasChanges: Bool
    let onAttempt: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        controller.hasChanges = hasChanges
        controller.onAttempt = onAttempt
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.hasChanges = hasChanges
        controller.onAttempt = onAttempt
        controller.installDelegateIfNeeded()
    }

    final class Controller: UIViewController, UIAdaptivePresentationControllerDelegate {
        var hasChanges = false
        var onAttempt: () -> Void = {}

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            installDelegateIfNeeded()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            installDelegateIfNeeded()
        }

        /// 自分から親をたどり、シート本体の presentationController を探す。
        /// 子のコントローラーも同じ型の presentationController を持つため、
        /// presentedViewController がそのコントローラー自身になるものを選ぶ。
        func installDelegateIfNeeded() {
            var controller: UIViewController? = self
            var target: UIPresentationController?
            while let current = controller {
                if let presentationController = current.presentationController,
                   presentationController.presentedViewController === current {
                    target = presentationController
                }
                controller = current.parent
            }
            target?.delegate = self
        }

        func presentationControllerShouldDismiss(
            _ presentationController: UIPresentationController
        ) -> Bool {
            return !hasChanges
        }

        func presentationControllerDidAttemptToDismiss(
            _ presentationController: UIPresentationController
        ) {
            onAttempt()
        }
    }
}
