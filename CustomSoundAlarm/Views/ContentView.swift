import SwiftUI
import StoreKit

/// 追加画面への要求（sheet(item:) 用・#101）
struct AddAlarmRequest: Identifiable {
    let id = UUID()
    let source: OnboardingSource?
}

/// メイン画面：アラーム一覧
/// OOUIの原則に従い、主オブジェクト（アラーム）のみを表示
struct ContentView: View {
    @State private var alarmStore = AlarmStore.shared
    @State private var soundStore = SoundStore.shared
    @State private var selectedAlarm: AlarmEntry?
    @State private var showingBedsideClock = false
    /// オンボの表示（#98）。初回評価は .task で1回だけ
    @State private var showingOnboarding = false
    /// オンボ場面4で選ばれた取り込み入口（追加画面に伝える・#98 Phase 4）
    @State private var addAlarmRequest: AddAlarmRequest?
    /// アップデート案内（#116）
    @State private var updateChecker = UpdateChecker.shared
    /// 休みのシート（#197）
    @State private var skipSelectionGroup: AlarmSkipLogic.DayGroup?
    @State private var showingSkipRange = false

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    if alarmStore.alarms.isEmpty {
                        emptyState
                    } else {
                        alarmList
                    }
                }
                .navigationTitle(String(localized: "alarm_title"))
                .toolbar(showingOnboarding ? .hidden : .visible, for: .tabBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingBedsideClock = true
                        } label: {
                            Image(systemName: "moon.zzz")
                        }
                        .accessibilityLabel(Text("night_mode"))
                        .accessibilityIdentifier("alarmList.bedside")
                    }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addAlarmRequest = AddAlarmRequest(source: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("add_alarm"))
                    .accessibilityIdentifier("alarmList.add")
                }
                }
                .task {
                    evaluateOnboarding()
                    #if DEBUG
                    if AppGroup.isUITestOpenAddAlarm {
                        addAlarmRequest = AddAlarmRequest(source: nil)
                    } else if AppGroup.isUITestOpenEditAlarm,
                              let alarm = alarmStore.alarms.first {
                        selectedAlarm = alarm
                    }
                    #endif
                    await updateChecker.check(isOnboardingVisible: showingOnboarding)
                }
                .safeAreaInset(edge: .bottom) {
                    AdSlot(slot: .bannerAlarmList)
                }

                if showingOnboarding {
                    OnboardingView { source in
                        AppGroup.hasCompletedOnboarding = true
                        withAnimation { showingOnboarding = false }
                        if source.opensAddScreen {
                            addAlarmRequest = AddAlarmRequest(source: source)
                        }
                        Task {
                            await updateChecker.check(isOnboardingVisible: false)
                        }
                    }
                    .environment(\.colorScheme, .light)
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .sheet(item: $addAlarmRequest) { request in
                AlarmDetailView(mode: .add, initialImport: request.source)
            }
            .sheet(item: $selectedAlarm) { alarm in
                AlarmDetailView(mode: .edit(alarm))
            }
            .fullScreenCover(isPresented: $showingBedsideClock) {
                BedsideClockView()
            }
            .fullScreenCover(item: requiredPromptBinding) { prompt in
                UpdatePromptView(
                    prompt: prompt,
                    onUpdate: { updateChecker.handleUpdateTap() },
                    onLater: nil
                )
            }
            .sheet(item: recommendedPromptBinding) { prompt in
                UpdatePromptView(
                    prompt: prompt,
                    onUpdate: { updateChecker.handleUpdateTap() },
                    onLater: { updateChecker.dismissRecommended() }
                )
                .presentationDetents([.medium])
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // ユーザーが自ら落ち着いてアプリを前面に出したタイミングで、
            // 定着ユーザー（発火実績あり・同一バージョン未依頼・当セッションで発火なし）にのみ
            // App Store レビューを依頼する。実際に表示するか否かは OS が最終判断する。
            guard phase == .active else { return }
            ReviewRequestManager.shared.requestReviewIfAppropriate {
                requestReview()
            }
            Task {
                await updateChecker.check(isOnboardingVisible: showingOnboarding)
            }
        }
    }

    // MARK: - Update prompt bindings (#116)

    /// 必須は閉じられない（setter は何もしない）
    private var requiredPromptBinding: Binding<UpdatePrompt?> {
        Binding(
            get: { updateChecker.prompt?.kind == .required ? updateChecker.prompt : nil },
            set: { _ in }
        )
    }

    /// おすすめは「あとで」/スワイプで閉じる（同じ latest_build では再表示しない）
    private var recommendedPromptBinding: Binding<UpdatePrompt?> {
        Binding(
            get: { updateChecker.prompt?.kind == .recommended ? updateChecker.prompt : nil },
            set: { newValue in
                if newValue == nil {
                    updateChecker.dismissRecommended()
                }
            }
        )
    }

    /// オンボの表示判定（#98 Phase 1/2）。
    /// 既存ユーザー（条件を満たさない）はここで完了扱いにして以後出さない
    private func evaluateOnboarding() {
#if DEBUG
        let effectiveHasCompleted: Bool
        if AppGroup.isUITestUpdateRequired || AppGroup.isUITestUpdateRecommended {
            effectiveHasCompleted = true
        } else if AppGroup.isUITestFreshOnboarding {
            effectiveHasCompleted = false
        } else {
            effectiveHasCompleted = AppGroup.hasCompletedOnboarding
        }
#else
        let effectiveHasCompleted = AppGroup.hasCompletedOnboarding
#endif
        let shows = OnboardingLogic.shouldShow(
            hasCompleted: effectiveHasCompleted,
            alarmCount: alarmStore.alarms.count,
            importedSoundCount: soundStore.sounds.filter { !$0.isPreset }.count
        )
        if shows {
            showingOnboarding = true
        } else if OnboardingLogic.shouldMarkCompleted(
            hasCompleted: AppGroup.hasCompletedOnboarding,
            shouldShowOnboarding: shows
        ) {
            AppGroup.hasCompletedOnboarding = true
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
            Text("empty_description")
        } actions: {
            Button {
                addAlarmRequest = AddAlarmRequest(source: nil)
            } label: {
                Text("add_alarm")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.actionFillEnd)
        }
        .accessibilityIdentifier("empty.title")
    }

    // MARK: - Skip (#197)

    /// 一覧の一番上に出す「次に鳴る日」。
    private var nextSkipDayGroup: AlarmSkipLogic.DayGroup? {
        AlarmSkipLogic.upcomingDayGroups(
            entries: alarmStore.alarms,
            after: Date(),
            limit: 1
        ).first
    }

    /// 休みにした日の案内（その日が終わるまで）。
    private var skipNotice: AlarmSkipLogic.Notice? {
        AlarmSkipLogic.activeNotice(entries: alarmStore.alarms, now: Date())
    }

    // MARK: - Alarm List

    private var alarmList: some View {
        let displayed = AlarmListOrdering.sortedForDisplay(alarmStore.alarms)
        return List {
            if let group = nextSkipDayGroup {
                AlarmSkipDaySection(
                    group: group,
                    onSelect: { skipSelectionGroup = group },
                    onRange: { showingSkipRange = true }
                )
                .warmCard()
            }
            if let notice = skipNotice {
                AlarmSkipNoticeView(notice: notice) {
                    AlarmSkipService.undo(dateKey: notice.dateKey)
                }
                .warmCard()
            }
            ForEach(displayed, id: \.id) { alarm in
                AlarmRow(
                    alarm: alarm,
                    soundName: AlarmSoundDisplay.name(for: alarm),
                    sound: AlarmSoundDisplay.representativeSound(for: alarm),
                    onToggle: {
                        alarmStore.toggleEnabled(alarm)
                        AlarmScheduler.shared.syncAlarms(alarmStore.alarms, trigger: .edit)
                    },
                    onTap: {
                        selectedAlarm = alarm
                    }
                )
                .warmCard()
                .contextMenu {
                    Button {
                        alarmStore.duplicate(alarm)
                        AlarmScheduler.shared.syncAlarms(alarmStore.alarms, trigger: .edit)
                    } label: {
                        Label("duplicate_alarm", systemImage: "plus.square.on.square")
                    }
                }
            }
            .onDelete { indexSet in
                let idsToDelete = indexSet.map { displayed[$0].id }
                for id in idsToDelete {
                    if let alarm = alarmStore.alarms.first(where: { $0.id == id }) {
                        alarmStore.remove(alarm)
                    }
                }
                AlarmScheduler.shared.syncAlarms(alarmStore.alarms, trigger: .edit)
            }
        }
        .animation(.default, value: alarmStore.alarms)
        .warmListBackground()
        .sheet(item: $skipSelectionGroup) { group in
            AlarmSkipSelectionSheet(date: group.date, entries: group.entries)
        }
        .sheet(isPresented: $showingSkipRange) {
            AlarmSkipPeriodSheet()
        }
    }

}

// MARK: - AlarmRow

struct AlarmRow: View {
    let alarm: AlarmEntry
    let soundName: String
    let sound: AlarmSound?
    let onToggle: () -> Void
    let onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onTap) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    accessibilityLayout
                } else {
                    regularLayout
                }
            }
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 4)
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Layouts

    /// 通常サイズ: サムネイル＋時刻＋補足＋トグルを横に並べる。
    private var regularLayout: some View {
        HStack(spacing: 12) {
            SoundThumbnail(sound: sound, size: 40, isDimmed: !alarm.isEnabled)

            VStack(alignment: .leading, spacing: 3) {
                timeText
                if !alarm.label.isEmpty {
                    Text(alarm.label)
                        .font(.subheadline)
                        .foregroundStyle(labelColor)
                        .lineLimit(1)
                }
                metadataLine(vertical: false)
                if let holidaySummary {
                    Text(holidaySummary)
                        .font(.caption)
                        .foregroundStyle(metaColor)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)
            toggle
        }
    }

    /// AX サイズ: 時刻を Dynamic Type に追従させ、ラベル・音名は切らずに縦へ。
    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                SoundThumbnail(sound: sound, size: 28, isDimmed: !alarm.isEnabled)
                timeText
                Spacer(minLength: 8)
                toggle
            }

            if !alarm.label.isEmpty {
                Text(alarm.label)
                    .font(.body)
                    .foregroundStyle(labelColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            metadataLine(vertical: true)
            if let holidaySummary {
                Text(holidaySummary)
                    .font(.caption)
                    .foregroundStyle(metaColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var timeText: some View {
        Text(alarm.timeString)
            .font(
                dynamicTypeSize.isAccessibilitySize
                    ? .system(.largeTitle, design: .rounded).weight(.regular)
                    : .system(size: 44, weight: .regular, design: .rounded)
            )
            .foregroundStyle(timeColor)
            .lineLimit(1)
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.7 : 1)
            // 長い音名のキャプションが幅を奪っても時刻は必ず自然サイズで描画されるよう優先
            .layoutPriority(1)
    }

    /// 1行目＝ラベル、2行目＝「曜日・音」（#174 PR-2）。
    /// AX では折り返して「…」で切らない。
    @ViewBuilder
    private func metadataLine(vertical: Bool) -> some View {
        if vertical {
            VStack(alignment: .leading, spacing: 2) {
                if !alarm.repeatWeekdays.isEmpty {
                    Text(repeatSummary)
                }
                HStack(spacing: 6) {
                    SoundIndicator(isCustom: AlarmSoundDisplay.isCustom(alarm), size: 10)
                    Text(soundDisplayName)
                        .fixedSize(horizontal: false, vertical: true)
                    if alarm.backupMinutes != nil {
                        Image(systemName: "bell.badge.fill")
                            .accessibilityLabel(Text("backup_alarm_row_badge"))
                    }
                }
            }
            .font(.body)
            .foregroundStyle(metaColor)
        } else {
            HStack(spacing: 6) {
                if !alarm.repeatWeekdays.isEmpty {
                    Text(repeatSummary)
                    Text("・")
                }
                SoundIndicator(isCustom: AlarmSoundDisplay.isCustom(alarm), size: 10)
                Text(soundDisplayName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if alarm.backupMinutes != nil {
                    Image(systemName: "bell.badge.fill")
                        .accessibilityLabel(Text("backup_alarm_row_badge"))
                }
            }
            .font(.footnote)
            .foregroundStyle(metaColor)
            .lineLimit(1)
        }
    }

    private var toggle: some View {
        Toggle("", isOn: Binding(
            get: { alarm.isEnabled },
            set: { _ in onToggle() }
        ))
        .labelsHidden()
        .tint(Brand.orange)
        .accessibilityLabel(Text(AlarmRowAccessibility.toggleLabel(
            time: alarm.timeString,
            label: alarm.label
        )))
    }

    private var timeColor: Color {
        alarm.isEnabled ? .primary : .textMuted
    }

    private var labelColor: Color {
        alarm.isEnabled ? .primary : .textMuted
    }

    private var metaColor: Color {
        alarm.isEnabled ? .textSecondary : .textMuted
    }

    private var soundDisplayName: String {
        soundName.isEmpty ? String(localized: "default_sound") : soundName
    }

    private var holidaySummary: String? {
        guard alarm.skipsHolidays,
              let holiday = AlarmSkipLogic.nextSkippedHoliday(for: alarm, after: Date())
        else { return nil }
        return String(
            format: String(localized: "holiday_next_skipped"),
            AlarmSkipFormat.holiday(holiday)
        )
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
