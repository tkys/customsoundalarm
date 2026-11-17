import SwiftUI
import StoreKit
import UIKit
import Accessibility

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
    @State private var showingSettings = false
    /// オンボの表示（#98）。初回評価は .task で1回だけ
    @State private var showingOnboarding = false
    /// オンボ場面4で選ばれた取り込み入口（追加画面に伝える・#98 Phase 4）
    @State private var addAlarmRequest: AddAlarmRequest?
    /// アップデート案内（#116）
    @State private var updateChecker = UpdateChecker.shared
    /// 共有シートから受け取った音の切り取り（#222）
    @State private var shareImportItem: ShareImportItem?
    @State private var shareImportSelectedSound: AlarmSound?
    @State private var shareImportDidFinish = false
    /// 共有経路の音量の1行（#224 / #222）
    @State private var shareImportVolumeBoostedFileName: String?
    /// プレイリストの解放（#216）
    @State private var unlock = PlaylistUnlockCoordinator.shared
    /// 許可状態（#230）
    @State private var scheduler = AlarmScheduler.shared
    /// 追加・編集画面が実際に開いているか（sheet の item より確実・#216）
    @State private var addScreenVisible = false
    @State private var editScreenVisible = false
    /// すべてのアラームを休む（#197 画面作り直し）
    @State private var showingSkipAll = false
    @State private var globalSkip: GlobalSkip?
    /// 許可バナーの表示済み計測（#230）
    @State private var reportedPermissionBannerStatus: AlarmPermissionStatus?
    @State private var skipToast: String?
    @State private var skipToastTask: Task<Void, Never>?
    @ScaledMetric(relativeTo: .body) private var skipActionIconSize: CGFloat = 17

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel(Text("settings"))
                        .accessibilityIdentifier("alarmList.settings")
                    }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if alarmStore.alarms.contains(where: \.isEnabled) {
                        Button {
                            showingSkipAll = true
                        } label: {
                            AlarmOffIcon()
                        }
                        .foregroundStyle(isGlobalSkipActive ? Brand.orange : Color.primary)
                        .accessibilityLabel(Text("skip_all_button"))
                        .accessibilityIdentifier("alarmList.skipAll")
                    }
                    Button {
                        addScreenVisible = true
                        addAlarmRequest = AddAlarmRequest(source: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("add_alarm"))
                    .accessibilityIdentifier("alarmList.add")
                }
                }
                .task {
                    refreshGlobalSkip()
                    syncSkipTimeZoneIfNeeded()
                    evaluateOnboarding()
                    presentNextShareImportIfNeeded()
                    scheduler.refreshPermissionStatus()
                    reportPermissionBannerIfNeeded()
                    #if DEBUG
                    if AppGroup.isUITestOpenAddAlarm {
                        addScreenVisible = true
                        addAlarmRequest = AddAlarmRequest(source: nil)
                    } else if AppGroup.isUITestOpenEditAlarm,
                              let alarm = alarmStore.alarms.first {
                        editScreenVisible = true
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
                            addScreenVisible = true
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
            .sheet(item: $addAlarmRequest, onDismiss: {
                addScreenVisible = false
                addAlarmRequest = nil
                schedulePlaylistUnlockAttempt()
            }) { request in
                AlarmDetailView(
                    mode: .add,
                    initialImport: request.source,
                    onClose: {
                        addScreenVisible = false
                        addAlarmRequest = nil
                        schedulePlaylistUnlockAttempt()
                    }
                )
                    .onDisappear {
                        addScreenVisible = false
                        addAlarmRequest = nil
                        schedulePlaylistUnlockAttempt()
                    }
            }
            .sheet(item: $selectedAlarm, onDismiss: {
                editScreenVisible = false
                selectedAlarm = nil
                schedulePlaylistUnlockAttempt()
            }) { alarm in
                AlarmDetailView(
                    mode: .edit(alarm),
                    onClose: {
                        editScreenVisible = false
                        selectedAlarm = nil
                        schedulePlaylistUnlockAttempt()
                    }
                )
                    .onDisappear {
                        editScreenVisible = false
                        selectedAlarm = nil
                        schedulePlaylistUnlockAttempt()
                    }
            }
            .sheet(isPresented: $showingSettings, onDismiss: {
                schedulePlaylistUnlockAttempt()
            }) {
                SettingsView()
            }
            .sheet(item: $shareImportItem, onDismiss: {
                let finished = shareImportDidFinish
                shareImportItem = nil
                shareImportSelectedSound = nil
                shareImportDidFinish = false
                if finished {
                    // 複数を共有したときは、1つずつ順に開く（#222）
                    Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        presentNextShareImportIfNeeded()
                    }
                }
            }) { item in
                NavigationStack {
                    shareImportContent(item)
                }
                .interactiveDismissDisabled()
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
            syncSkipTimeZoneIfNeeded()
            refreshGlobalSkip()
            presentNextShareImportIfNeeded()
            let wasAuthorized = scheduler.permissionStatus == .authorized
            scheduler.refreshPermissionStatus()
            if !wasAuthorized, scheduler.permissionStatus == .authorized {
                scheduler.syncAlarms(alarmStore.alarms, trigger: .foreground)
            }
            reportPermissionBannerIfNeeded()
            ReviewRequestManager.shared.requestReviewIfAppropriate {
                requestReview()
            }
            Task {
                await updateChecker.check(isOnboardingVisible: showingOnboarding)
            }
        }
        .overlay(alignment: .bottom) {
            if let skipToast {
                SaveConfirmationToast(text: skipToast)
                    .padding(.horizontal, 16)
                    .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 100 : 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityIdentifier("skip.row.toast")
            }
        }
        .animation(.easeInOut(duration: 0.25), value: skipToast)
        .onChange(of: soundStore.hasPendingPlaylistUnlock) { _, hasPending in
            if hasPending { schedulePlaylistUnlockAttempt() }
        }
        .onChange(of: addScreenVisible) { _, isVisible in
            if !isVisible { schedulePlaylistUnlockAttempt() }
        }
        .onChange(of: editScreenVisible) { _, isVisible in
            if !isVisible { schedulePlaylistUnlockAttempt() }
        }
        .onChange(of: showingSettings) { _, isShowing in
            if !isShowing {
                schedulePlaylistUnlockAttempt()
                presentNextShareImportIfNeeded()
            }
        }
        .onChange(of: scheduler.isAlarmRinging) { _, isRinging in
            if !isRinging {
                schedulePlaylistUnlockAttempt()
                presentNextShareImportIfNeeded()
            }
        }
        .onChange(of: showingOnboarding) { _, isShowing in
            if !isShowing { presentNextShareImportIfNeeded() }
        }
        .onChange(of: addAlarmRequest == nil) { _, isClosed in
            if isClosed { presentNextShareImportIfNeeded() }
        }
        .onChange(of: selectedAlarm == nil) { _, isClosed in
            if isClosed { presentNextShareImportIfNeeded() }
        }
        .onChange(of: updateChecker.prompt == nil) { _, isClosed in
            if isClosed { presentNextShareImportIfNeeded() }
        }
    }

    // MARK: - Shared Imports (#222)

    @ViewBuilder
    private func shareImportContent(_ item: ShareImportItem) -> some View {
        switch item.mediaKind {
        case .audio:
            AudioCropView(
                source: PendingAudioImport(url: item.mediaURL, name: item.displayName),
                selectedSound: $shareImportSelectedSound,
                customSoundSource: .share,
                shareMedia: .audio,
                onSaved: {
                    ShareImportQueue.complete(item)
                    shareImportDidFinish = true
                },
                onUserClosed: {
                    ShareImportQueue.complete(item)
                    shareImportDidFinish = true
                },
                deletesSourceOnDiscard: false,
                volumeBoostedFileName: $shareImportVolumeBoostedFileName
            )
        case .video:
            VideoImportFlow(
                selectedSound: $shareImportSelectedSound,
                initialFileURL: item.mediaURL,
                customSoundSource: .share,
                shareMedia: .video,
                onSaved: {
                    ShareImportQueue.complete(item)
                    shareImportDidFinish = true
                },
                onUserClosed: {
                    ShareImportQueue.complete(item)
                    shareImportDidFinish = true
                },
                volumeBoostedFileName: $shareImportVolumeBoostedFileName
            )
        }
    }

    /// 共有された音の切り取り画面を、落ち着いているときだけ1件ずつ開く（#222）。
    private func presentNextShareImportIfNeeded() {
        guard shareImportItem == nil,
              addAlarmRequest == nil,
              selectedAlarm == nil,
              !showingSettings,
              !showingOnboarding,
              updateChecker.prompt == nil,
              !scheduler.isAlarmRinging else { return }
        guard let item = ShareImportQueue.pendingItems().first else { return }
        shareImportDidFinish = false
        shareImportItem = item
    }

    /// 追加・編集・設定などのシートが閉じてから解放シートを出す（#216）。
    private func schedulePlaylistUnlockAttempt() {
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            attemptPlaylistUnlock()
        }
    }

    private func attemptPlaylistUnlock() {
        guard !addScreenVisible,
              !editScreenVisible,
              !showingSettings,
              !showingOnboarding,
              updateChecker.prompt == nil else { return }
        _ = unlock.presentIfNeeded(
            isRinging: scheduler.isAlarmRinging,
            isNightMode: BedsideModeTracker.shared.isActive
        )
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
                addScreenVisible = true
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

    private var isGlobalSkipActive: Bool {
        globalSkip?.isActive == true
    }

    private var activeGlobalSkip: GlobalSkip? {
        guard let globalSkip, globalSkip.isActive else { return nil }
        return globalSkip
    }

    private func refreshGlobalSkip() {
        if let skip = AppGroup.globalSkip, !skip.isActive {
            AppGroup.globalSkip = nil
        }
        globalSkip = AppGroup.globalSkip
    }

    /// タイムゾーンが変わったら、補いのアラームを登録し直す（#197）。
    private func syncSkipTimeZoneIfNeeded() {
        let current = TimeZone.current.identifier
        let previous = AppGroup.lastSkipTimeZone
        AppGroup.lastSkipTimeZone = current
        guard let previous, previous != current else { return }
        let hasSkip = AppGroup.globalSkip != nil
            || alarmStore.alarms.contains { !$0.skipDates.isEmpty || $0.skipsHolidays }
        guard hasSkip else { return }
        AlarmScheduler.shared.syncAlarms(alarmStore.alarms, trigger: .edit)
    }

    // MARK: - Alarm List

    private var alarmList: some View {
        let displayed = AlarmListOrdering.sortedForDisplay(alarmStore.alarms)
        return List {
            if let permissionStatus = permissionBannerStatus {
                permissionBannerRow(permissionStatus)
            }
            if let skip = activeGlobalSkip {
                GlobalSkipNoticeRow(
                    skip: skip,
                    entries: alarmStore.alarms,
                    onUndo: {
                        AlarmSkipService.undoAll()
                        refreshGlobalSkip()
                    }
                )
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
                        refreshGlobalSkip()
                    },
                    onTap: {
                        editScreenVisible = true
                        selectedAlarm = alarm
                    }
                )
                .warmCard()
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if !alarm.repeatWeekdays.isEmpty {
                        skipSwipeAction(for: alarm)
                    }
                }
                .contextMenu {
                    if !alarm.repeatWeekdays.isEmpty {
                        skipMenuButton(for: alarm)
                    }
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
                refreshGlobalSkip()
            }
        }
        .animation(.default, value: alarmStore.alarms)
        .warmListBackground()
        .sheet(isPresented: $showingSkipAll, onDismiss: refreshGlobalSkip) {
            SkipAllSheet(entries: alarmStore.alarms.filter(\.isEnabled))
        }
    }

    // MARK: - Permission Banner (#230)

    /// 許可が拒否済み／未確認で、オンのアラームがあるときだけ出す。
    private var permissionBannerStatus: AlarmPermissionStatus? {
        let enabledCount = alarmStore.alarms.filter(\.isEnabled).count
        guard PermissionBannerLogic.shouldShow(
            status: scheduler.permissionStatus,
            enabledAlarmCount: enabledCount
        ) else { return nil }
        return scheduler.permissionStatus
    }

    @ViewBuilder
    private func permissionBannerRow(_ status: AlarmPermissionStatus) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    warningIcon
                    permissionBannerTitle
                }
                Button("permission_banner_allow") {
                    handlePermissionBannerTap(status)
                }
                .buttonStyle(.borderless)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier("alarmList.permissionAllow")
            }
            .warmCard()
        } else {
            HStack(spacing: 8) {
                warningIcon
                permissionBannerTitle
                Spacer()
                Button("permission_banner_allow") {
                    handlePermissionBannerTap(status)
                }
                .buttonStyle(.borderless)
                .font(.subheadline.weight(.medium))
                .accessibilityIdentifier("alarmList.permissionAllow")
            }
            .warmCard()
        }
    }

    private var warningIcon: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
    }

    private var permissionBannerTitle: some View {
        Text("permission_banner_title")
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("alarmList.permissionBanner")
    }

    private func handlePermissionBannerTap(_ status: AlarmPermissionStatus) {
        AnalyticsService.shared.capture(.permissionBannerTapped(status: status))
        switch PermissionBannerLogic.action(for: status) {
        case .openSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        case .requestAuthorization:
            Task {
                let granted = await scheduler.requestAuthorization()
                scheduler.refreshPermissionStatus()
                if granted {
                    scheduler.syncAlarms(alarmStore.alarms, trigger: .foreground)
                }
                reportPermissionBannerIfNeeded()
            }
        case nil:
            break
        }
    }

    private func reportPermissionBannerIfNeeded() {
        guard let status = permissionBannerStatus else {
            reportedPermissionBannerStatus = nil
            return
        }
        guard reportedPermissionBannerStatus != status else { return }
        reportedPermissionBannerStatus = status
        AnalyticsService.shared.capture(.permissionBannerShown(status: status))
    }

    private func skipNextWithToast(_ alarm: AlarmEntry) {
        guard let next = AlarmSkipLogic.nextFireDate(for: alarm, after: Date()) else {
            return
        }
        AlarmSkipService.skipNext(entryID: alarm.id)
        showSkipToast(String(
            format: String(localized: "skip_row_toast_skipped_fmt"),
            AlarmSkipFormat.day(next)
        ))
    }

    private func undoNextWithToast(_ alarm: AlarmEntry) {
        guard let skipped = AlarmSkipLogic.nextIndividualSkipDate(
            for: alarm,
            after: Date()
        ) else { return }
        AlarmSkipService.undoNext(entryID: alarm.id)
        showSkipToast(String(
            format: String(localized: "skip_row_toast_undone_fmt"),
            AlarmSkipFormat.day(skipped)
        ))
    }

    private func showSkipToast(_ text: String) {
        skipToastTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            skipToast = text
        }
        AccessibilityNotification.Announcement(text).post()
        skipToastTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2500))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                skipToast = nil
            }
        }
    }

    @ViewBuilder
    private func skipSwipeAction(for alarm: AlarmEntry) -> some View {
        if AlarmSkipLogic.nextIndividualSkipDate(for: alarm, after: Date()) != nil {
            Button {
                undoNextWithToast(alarm)
            } label: {
                Label {
                    Text("skip_row_undo")
                } icon: {
                    Image(systemName: "alarm")
                }
            }
            .tint(Color.textSecondary)
            .accessibilityIdentifier("skip.row.undo.\(alarm.id.uuidString)")
        } else if let next = AlarmSkipLogic.nextFireDate(for: alarm, after: Date()) {
            Button {
                skipNextWithToast(alarm)
            } label: {
                Label {
                    Text(String(
                        format: String(localized: "skip_row_skip_fmt"),
                        AlarmSkipFormat.day(next)
                    ))
                } icon: {
                    skipActionIcon()
                }
            }
            .tint(Brand.orange)
            .accessibilityIdentifier("skip.row.skip.\(alarm.id.uuidString)")
        }
    }

    @ViewBuilder
    private func skipActionIcon() -> some View {
        if let image = AlarmOffIconRenderer.image(pointSize: skipActionIconSize) {
            Image(uiImage: image)
                .renderingMode(.template)
        } else {
            Image(systemName: "alarm")
        }
    }

    @ViewBuilder
    private func skipMenuButton(for alarm: AlarmEntry) -> some View {
        if AlarmSkipLogic.nextIndividualSkipDate(for: alarm, after: Date()) != nil {
            Button {
                undoNextWithToast(alarm)
            } label: {
                Label {
                    Text("skip_row_undo")
                } icon: {
                    Image(systemName: "alarm")
                }
            }
        } else if let next = AlarmSkipLogic.nextFireDate(for: alarm, after: Date()) {
            Button {
                skipNextWithToast(alarm)
            } label: {
                Label {
                    Text(String(
                        format: String(localized: "skip_row_skip_fmt"),
                        AlarmSkipFormat.day(next)
                    ))
                } icon: {
                    skipActionIcon()
                }
            }
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
        .accessibilityIdentifier("alarm.row")
    }

    // MARK: - Layouts

    /// 通常サイズ: サムネイル＋時刻＋補足＋トグルを横に並べる。
    private var regularLayout: some View {
        HStack(spacing: 12) {
            SoundThumbnail(sound: sound, size: 40, isDimmed: !alarm.isEnabled)

            VStack(alignment: .leading, spacing: 3) {
                timeText
                if let skipSummaryText {
                    Text(skipSummaryText)
                        .font(.caption)
                        .foregroundStyle(metaColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("skip.row.summary")
                }
                if let globalSkipSummaryText {
                    Text(globalSkipSummaryText)
                        .font(.caption)
                        .foregroundStyle(metaColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("skip.row.globalSummary")
                }
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
                        .accessibilityIdentifier("holiday.summary")
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

            if let skipSummaryText {
                Text(skipSummaryText)
                    .font(.caption)
                    .foregroundStyle(metaColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("skip.row.summary")
            }

            if let globalSkipSummaryText {
                Text(globalSkipSummaryText)
                    .font(.caption)
                    .foregroundStyle(metaColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("skip.row.globalSummary")
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
                    .accessibilityIdentifier("holiday.summary")
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

    private var skipSummaryText: String? {
        guard let summary = AlarmSkipLogic.individualSkipSummary(
            for: alarm,
            after: Date()
        ) else { return nil }
        if let next = summary.next {
            return String(
                format: String(localized: "skip_row_summary_fmt"),
                AlarmSkipFormat.day(summary.skipped),
                AlarmSkipFormat.day(next)
            )
        }
        return String(
            format: String(localized: "skip_row_summary_no_next_fmt"),
            AlarmSkipFormat.day(summary.skipped)
        )
    }

    private var globalSkipSummaryText: String? {
        guard let end = AlarmSkipLogic.globalSkipRowEnd(for: alarm) else { return nil }
        return String(
            format: String(localized: "skip_row_global_fmt"),
            AlarmSkipFormat.dayAndTime(end)
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
