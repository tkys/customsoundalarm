import SwiftUI
import StoreKit
import UIKit
import Accessibility

/// 追加画面への要求（sheet(item:) 用・#101）
struct AddAlarmRequest: Identifiable {
    let id = UUID()
    let source: OnboardingSource?
    let initialSound: AlarmSound?

    init(source: OnboardingSource?, initialSound: AlarmSound? = nil) {
        self.source = source
        self.initialSound = initialSound
    }
}

/// 一覧で行を入れて光らせる要求（#282 / #198）。
private struct AlarmSpotlightRequest: Equatable {
    let token = UUID()
    let alarmIDs: [UUID]
}

/// 自分で動かすスクロールの開始・終了位置（#282 レビュー）。
private struct SpotlightScrollTarget {
    let from: CGFloat
    let to: CGFloat
    let isVisible: Bool
}

/// メイン画面：アラーム一覧
/// OOUIの原則に従い、主オブジェクト（アラーム）のみを表示
struct ContentView: View {
    /// コントロールセンターから開く要求（#272）。RootTabView が設定する。
    @Binding var controlOpenKind: ControlOpenKind?
    /// 作った・時刻を変えた行のスポットライト（#282）
    @State private var spotlightStore = RowSpotlightStore()
    @State private var alarmFrameStore = RowFrameStore<UUID>()
    @State private var spotlightViewport: CGRect = .zero
    /// 一覧に出す配列（#282 レビュー）。ForEach はこの1か所だけを見る。
    @State private var displayedAlarms: [AlarmEntry] = []
    /// スクロール中は高さ0にしておく行（#282 / #198）
    @State private var pendingRevealAlarmIDs: Set<UUID> = []
    /// 高さを開いた行（#282 / #198）
    @State private var revealedAlarmIDs: Set<UUID> = []
    /// 一覧の準備ができてから処理する演出要求（#282）
    @State private var spotlightRequest: AlarmSpotlightRequest?
    /// `List` の下の UIScrollView（#282 レビュー）
    @State private var listScrollView: UIScrollView?
    @State private var scrollAnimator = SpotlightScrollAnimator()
    @AccessibilityFocusState private var spotlightFocusedAlarmID: UUID?
    @State private var alarmStore = AlarmStore.shared
    @State private var soundStore = SoundStore.shared
    @State private var selectedAlarm: AlarmEntry?
    @State private var showingSettings = false
    /// オンボの表示（#98）。初回評価は .task で1回だけ
    @State private var showingOnboarding = false
    /// オンボーディング判定が終わったか（コントロールの着地先を決めるため・#272）
    @State private var didEvaluateOnboarding = false
    /// オンボ場面4で選ばれた取り込み入口（追加画面に伝える・#98 Phase 4）
    @State private var addAlarmRequest: AddAlarmRequest?
    /// アップデート案内（#116）
    @State private var updateChecker = UpdateChecker.shared
    /// 共有シートから受け取った音の切り取り（#222）
    @State private var shareImportItem: ShareImportItem?
    @State private var shareImportSelectedSound: AlarmSound?
    @State private var shareImportDidFinish = false
    @State private var shareLanding = ShareImportLanding.shared
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
    /// 設定アプリへ移る前のシート（#239）
    @State private var showingPermissionSettings = false
    /// 許可がオンになったときの触覚（#239）
    @State private var permissionFeedbackTrigger = 0
    @State private var skipToast: String?
    @State private var skipToastTask: Task<Void, Never>?
    /// 空の一覧から作ったときの保存後の一言（#231）
    @State private var quickSaveToast: String?
    @State private var quickSaveToastTask: Task<Void, Never>?
    @State private var quickSaveFeedbackTrigger = 0
    /// 無音の音を使っている既存アラーム（#256）
    @State private var silentAlarmLevels: [UUID: SilentSoundLevel] = [:]
    @State private var fixingSilentAlarm: AlarmEntry?
    @State private var didScanSilentAlarms = false
    /// 初めての1回きりアラームの提案を出す行（#247）
    @State private var firstAlarmFollowupAlarmID: UUID?
    @ScaledMetric(relativeTo: .body) private var skipActionIconSize: CGFloat = 17

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @MainActor
    init(controlOpenKind: Binding<ControlOpenKind?>) {
        _controlOpenKind = controlOpenKind
        // 起動直後に一覧が空で描画されないよう、今の保存内容から始める（#282 レビュー）
        _displayedAlarms = State(
            initialValue: AlarmListOrdering.sortedForDisplay(AlarmStore.shared.alarms)
        )
    }

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
                            ignoreFirstAlarmFollowupIfNeeded()
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
                        ignoreFirstAlarmFollowupIfNeeded()
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
                    syncDisplayedAlarms()
                    evaluateOnboarding()
                    didEvaluateOnboarding = true
                    applyControlOpenIfNeeded()
                    presentNextShareImportIfNeeded()
                    scheduler.refreshPermissionStatus()
                    reportPermissionBannerIfNeeded()
                    scanSilentAlarms()
                    evaluateFirstAlarmFollowup()
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
                .onChange(of: controlOpenKind) { _, _ in
                    applyControlOpenIfNeeded()
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
                    initialSound: request.initialSound,
                    onClose: {
                        addScreenVisible = false
                        addAlarmRequest = nil
                        schedulePlaylistUnlockAttempt()
                    },
                    onSaved: { saved, shouldSpotlight in
                        handleAlarmSaved(saved, shouldSpotlight: shouldSpotlight)
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
                    },
                    onSaved: { saved, shouldSpotlight in
                        handleAlarmSaved(saved, shouldSpotlight: shouldSpotlight)
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
                let savedSound = shareImportSelectedSound
                shareImportItem = nil
                shareImportSelectedSound = nil
                shareImportDidFinish = false
                if finished {
                    Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        if !ShareImportQueue.pendingItems().isEmpty {
                            // 複数を共有したときは、1つずつ順に開く（#222）
                            presentNextShareImportIfNeeded()
                        } else if let savedSound {
                            landShareImport(savedSound)
                        }
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
            .sheet(item: $fixingSilentAlarm) { alarm in
                NavigationStack {
                    AlarmSoundChoiceView(
                        playlistID: Binding(
                            get: { alarmStore.alarms.first { $0.id == alarm.id }?.playlistID },
                            set: { _ in }
                        ),
                        selectedSound: Binding(
                            get: {
                                guard let fileName = alarmStore.alarms
                                    .first(where: { $0.id == alarm.id })?.soundFileName
                                else { return nil }
                                return soundStore.sounds.first { $0.fileName == fileName }
                            },
                            set: { _ in }
                        ),
                        volumeBoostedFileName: .constant(nil),
                        onSelection: { sound, playlistID in
                            repairSilentAlarm(alarm, sound: sound, playlistID: playlistID)
                        }
                    )
                }
            }
            .sheet(isPresented: $showingPermissionSettings) {
                PermissionSettingsSheet {
                    AnalyticsService.shared.capture(.permissionBannerTapped(
                        status: .denied,
                        step: .settingsOpened
                    ))
                    showingPermissionSettings = false
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .presentationDetents(
                    dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium]
                )
            }
        }
        .onChange(of: alarmStore.alarms) { _, _ in
            // ForEach に渡す配列は1か所でだけ更新する（#282 レビュー）
            syncDisplayedAlarms(animated: true)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                // 提案を見たまま一覧を離れたら、二度と出さない（#247）
                ignoreFirstAlarmFollowupIfNeeded()
                return
            }
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
                permissionFeedbackTrigger += 1
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
        .overlay(alignment: .bottom) {
            if let quickSaveToast {
                SaveConfirmationToast(text: quickSaveToast)
                    .padding(.horizontal, 16)
                    .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 100 : 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityIdentifier("emptyState.toast")
            }
        }
        .animation(.easeInOut(duration: 0.25), value: quickSaveToast)
        .animation(.easeInOut(duration: 0.25), value: skipToast)
        .sensoryFeedback(.success, trigger: permissionFeedbackTrigger)
        .sensoryFeedback(.success, trigger: quickSaveFeedbackTrigger)
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
        .onChange(of: shareLanding.addAlarmSound) { _, sound in
            guard let sound else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                addScreenVisible = true
                addAlarmRequest = AddAlarmRequest(source: nil, initialSound: sound)
                shareLanding.addAlarmSound = nil
            }
        }
        .onDisappear {
            // タブ移動などで一覧を離れたら、押されなかった提案は終わり（#247）
            ignoreFirstAlarmFollowupIfNeeded()
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
                initialSoundName: item.displayName,
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

    /// 最後の1件を保存したあとの着地先（#246）。
    private func landShareImport(_ sound: AlarmSound) {
        let destination: ShareImportDestination
        if alarmStore.alarms.isEmpty {
            destination = .addAlarm
            addScreenVisible = true
            addAlarmRequest = AddAlarmRequest(source: nil, initialSound: sound)
        } else {
            destination = .library
            ShareImportLanding.shared.librarySoundFileName = sound.fileName
        }
        AnalyticsService.shared.capture(.importLanded(
            source: .share,
            destination: destination
        ))
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

    /// コントロールからの要求を、オンボーディング判定後に反映する（#272）。
    private func applyControlOpenIfNeeded() {
        guard didEvaluateOnboarding, let kind = controlOpenKind else { return }
        controlOpenKind = nil
        switch ControlOpenLogic.destination(
            kind: kind,
            isOnboardingVisible: showingOnboarding
        ) {
        case .onboarding, .list:
            break
        case .add:
            addScreenVisible = true
            addAlarmRequest = AddAlarmRequest(source: nil)
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 20) {
                if colorScheme != .dark {
                    Image("onboarding_hero")
                        .resizable()
                        .scaledToFit()
                        .frame(height: dynamicTypeSize.isAccessibilitySize ? 110 : 160)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .accessibilityHidden(true)
                }

                Text("empty_quick_title")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                timeButtons

                Button("empty_quick_other") {
                    addScreenVisible = true
                    addAlarmRequest = AddAlarmRequest(source: nil)
                }
                .buttonStyle(.borderless)
                .font(.subheadline.weight(.medium))
                .tint(Color.actionText)
                .accessibilityIdentifier("emptyState.other")
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 100)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("emptyState.root")
    }

    @ViewBuilder
    private var timeButtons: some View {
        let times = EmptyStateQuickAlarmLogic.times
        if dynamicTypeSize.isAccessibilitySize {
            LazyVGrid(
                columns: [GridItem(.flexible())],
                spacing: 10
            ) {
                ForEach(times) { time in
                    quickTimeButton(time)
                }
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ForEach(times) { time in
                        quickTimeButton(time)
                    }
                }
                timeGrid(times)
            }
        }
    }

    private func timeGrid(_ times: [QuickAlarmTime]) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 10
        ) {
            ForEach(times) { time in
                quickTimeButton(time)
            }
        }
        .frame(maxWidth: 360)
    }

    private func quickTimeButton(_ time: QuickAlarmTime) -> some View {
        Button {
            createQuickAlarm(time)
        } label: {
            Text(time.label)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityHint(Text("empty_quick_hint"))
        .accessibilityIdentifier("emptyState.quick.\(time.id)")
    }

    /// 時刻を1回押して、明日の朝の一回限りのアラームを作る（#231）。
    private func createQuickAlarm(_ time: QuickAlarmTime) {
        let soundFileName = EmptyStateQuickAlarmLogic.soundFileName(
            imported: soundStore.sounds,
            lastUsedFileName: SoundUsageHistory.lastUsedFileName,
            availableFileNames: Set(soundStore.sounds.map(\.fileName))
        )
        let carryOver = AlarmCarryOverLogic.carryOver(
            from: AlarmCarryOverStore.last,
            playlistExists: { PlaylistStore.shared.playlist(id: $0) != nil }
        )
        let entry = EmptyStateQuickAlarmLogic.makeEntry(
            time: time,
            soundFileName: soundFileName,
            label: String(localized: "alarm_placeholder"),
            snoozeMinutes: carryOver.snoozeMinutes,
            fadeIn: carryOver.fadeIn
        )
        AlarmUIDStore.recordCreation(entry.id)
        alarmStore.add(entry)
        SoundUsageHistory.recordUsage(soundFileName)
        AlarmCarryOverStore.save(from: entry)

        var context = AlarmHistoryLogic.context(for: entry)
        context.list = AlarmHistoryLogic.listSnapshot([])
        let isCustomSound = soundStore.sounds
            .first { $0.fileName == soundFileName }?
            .isPreset == false
        AnalyticsService.shared.capture(.alarmCreated(
            hasCustomSound: isCustomSound,
            isRepeating: false,
            snoozeMinutes: entry.snoozeMinutes,
            backupMinutes: 0,
            soundMode: .single,
            fadeIn: .off,
            context: context,
            source: .emptyQuick
        ))

        AlarmScheduler.shared.syncAlarms(alarmStore.alarms, trigger: .edit)
        quickSaveFeedbackTrigger += 1

        if let message = PostSaveFeedback.resolve(for: entry, currentDate: Date())
            .localizedMessage(entry: entry, currentDate: Date()) {
            quickSaveToastTask?.cancel()
            quickSaveToast = message
            quickSaveToastTask = Task {
                try? await Task.sleep(for: .seconds(2))
                quickSaveToast = nil
            }
        }

        Task {
            if scheduler.permissionStatus == .notDetermined {
                _ = await scheduler.requestAuthorization()
                scheduler.refreshPermissionStatus()
                if scheduler.permissionStatus == .authorized {
                    AlarmScheduler.shared.syncAlarms(alarmStore.alarms, trigger: .foreground)
                }
            }
            reportPermissionBannerIfNeeded()
        }
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

    /// 一覧に出す配列を1か所で更新する（#282 レビュー）。
    private func syncDisplayedAlarms(animated: Bool = false) {
        let sorted = AlarmListOrdering.sortedForDisplay(alarmStore.alarms)
        guard sorted != displayedAlarms else { return }
        if animated {
            withAnimation(.default) {
                displayedAlarms = sorted
            }
        } else {
            displayedAlarms = sorted
        }
    }

    private var alarmList: some View {
        ScrollViewReader { proxy in
            List {
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
                ForEach(displayedAlarms, id: \.id) { alarm in
                    Group {
                        if pendingRevealAlarmIDs.contains(alarm.id) {
                            SpotlightRevealRow(
                                isRevealed: revealedAlarmIDs.contains(alarm.id),
                                reduceMotion: reduceMotion
                            ) {
                                alarmRowContent(alarm)
                            }
                        } else {
                            alarmRowContent(alarm)
                        }
                    }
                    .warmCard(spotlight: spotlightStore.controller(for: alarm.id))
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
                    // ForEach と同じ配列から対象を取り、変更は1回の withAnimation で行う（#282 レビュー）
                    let targets = indexSet.compactMap { index in
                        displayedAlarms.indices.contains(index)
                            ? displayedAlarms[index]
                            : nil
                    }
                    guard !targets.isEmpty else { return }
                    let ids = Set(targets.map(\.id))
                    // 先に一覧の配列を1回だけ更新し、List の削除更新と重ねない（#282 レビュー）
                    let remaining = AlarmListOrdering.sortedForDisplay(
                        alarmStore.alarms.filter { !ids.contains($0.id) }
                    )
                    withAnimation(.default) {
                        displayedAlarms = remaining
                    }
                    alarmStore.remove(targets)
                    AlarmScheduler.shared.syncAlarms(alarmStore.alarms, trigger: .edit)
                    refreshGlobalSkip()
                }

            }
            // 最後の行でも45%まで送れるよう、スクロール内容の下端に余白を持たせる（#282）
            .contentMargins(
                .bottom,
                RowSpotlightTiming.bottomScrollSpace,
                for: .scrollContent
            )
            .warmListBackground()
            .onGeometryChange(for: CGRect.self) { geometry in
                // 一覧として実際に見えている範囲（画面座標）。下端の広告・タブを除く。
                let frame = geometry.frame(in: .global)
                let insets = geometry.safeAreaInsets
                return CGRect(
                    x: frame.minX + insets.leading,
                    y: frame.minY + insets.top,
                    width: max(0, frame.width - insets.leading - insets.trailing),
                    height: max(0, frame.height - insets.top - insets.bottom)
                )
            } action: { viewport in
                spotlightViewport = viewport
            }
            .task(id: spotlightRequest) {
                guard let request = spotlightRequest else { return }
                await runSpotlight(request, proxy: proxy)
            }
            .sheet(isPresented: $showingSkipAll, onDismiss: refreshGlobalSkip) {
                SkipAllSheet(entries: alarmStore.alarms.filter(\.isEnabled))
            }
        }
    }

    // MARK: - Row spotlight (#282)

    /// 一覧の1行（スポットライトの対象でも同じ中身を使う）。
    private func alarmRowContent(_ alarm: AlarmEntry) -> some View {
        AlarmRow(
            alarm: alarm,
            soundName: AlarmSoundDisplay.name(for: alarm),
            sound: AlarmSoundDisplay.representativeSound(for: alarm),
            hasSilentSound: silentAlarmLevels[alarm.id] != nil,
            showsFirstAlarmFollowup: firstAlarmFollowupAlarmID == alarm.id,
            spotlight: spotlightStore.controller(for: alarm.id),
            spotlightFocus: $spotlightFocusedAlarmID,
            onFixSilentSound: {
                ignoreFirstAlarmFollowupIfNeeded()
                fixingSilentAlarm = alarm
            },
            onFirstAlarmFollowup: { action in
                applyFirstAlarmFollowup(action, to: alarm)
            },
            onToggle: {
                if firstAlarmFollowupAlarmID == alarm.id {
                    ignoreFirstAlarmFollowupIfNeeded()
                }
                alarmStore.toggleEnabled(alarm)
                AlarmScheduler.shared.syncAlarms(alarmStore.alarms, trigger: .edit)
                refreshGlobalSkip()
            },
            onTap: {
                ignoreFirstAlarmFollowupIfNeeded()
                editScreenVisible = true
                selectedAlarm = alarm
            }
        )
        .rowSpotlightFrame(alarm.id, into: alarmFrameStore)
        .background {
            // 行の下にある List の UIScrollView を取得する（#282 レビュー）
            ScrollViewResolver { scrollView in
                if listScrollView !== scrollView {
                    listScrollView = scrollView
                }
            }
        }
    }

    /// 保存された行を、スクロールが止まるまで高さ0で待たせる（#282）。
    private func handleAlarmSaved(_ alarm: AlarmEntry, shouldSpotlight: Bool) {
        guard shouldSpotlight else { return }

        // 前の演出が残っていたら、その行は出し切ってから次へ
        if !pendingRevealAlarmIDs.isEmpty {
            revealedAlarmIDs.formUnion(pendingRevealAlarmIDs)
            pendingRevealAlarmIDs.removeAll()
        }

        pendingRevealAlarmIDs.insert(alarm.id)
        revealedAlarmIDs.remove(alarm.id)
        spotlightRequest = AlarmSpotlightRequest(alarmIDs: [alarm.id])
    }

    /// 行の位置から、自分で動かすスクロールの開始・終了位置を求める（#282 レビュー）。
    private func spotlightScrollTarget(
        for alarmID: UUID,
        scrollView: UIScrollView
    ) -> SpotlightScrollTarget? {
        guard spotlightViewport.height > 0,
              let collectionView = scrollView as? UICollectionView,
              let index = displayedAlarms.firstIndex(where: { $0.id == alarmID })
        else { return nil }

        // 上に許可バナー・全体の休みの行があれば、その分だけ indexPath をずらす
        let leadingRows = (permissionBannerStatus != nil ? 1 : 0)
            + (activeGlobalSkip != nil ? 1 : 0)
        let indexPath = IndexPath(row: leadingRows + index, section: 0)
        // 追加直後は行のレイアウトが古いことがあるため、一度整えてから読む
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.layoutIfNeeded()
        #if DEBUG
        NSLog(
            "%@",
            String(
                format: "[SpotlightScroll] collection sections=%d rows0=%d index=%d indexPath=%@ offset=%.1f size=%.1fx%.1f bounds=%.1fx%.1f",
                collectionView.numberOfSections,
                collectionView.numberOfItems(inSection: 0),
                index,
                indexPath.description,
                Double(collectionView.contentOffset.y),
                Double(collectionView.contentSize.width),
                Double(collectionView.contentSize.height),
                Double(collectionView.bounds.width),
                Double(collectionView.bounds.height)
            )
        )
        #endif
        guard let attributes = collectionView.layoutAttributesForItem(at: indexPath)
            ?? collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)
        else { return nil }
        #if DEBUG
        NSLog(
            "%@",
            String(
                format: "[SpotlightScroll] attributes frame=%@ midY=%.1f",
                NSCoder.string(for: attributes.frame),
                Double(attributes.frame.midY)
            )
        )
        #endif

        let from = scrollView.contentOffset.y
        let naturalHeight = alarmFrameStore.frame(for: alarmID)?.height
            ?? max(attributes.frame.height, 96)
        let rowTop = attributes.frame.minY - from
        let rowBottom = rowTop + naturalHeight

        let scrollFrame = scrollView.convert(
            CGRect(origin: .zero, size: scrollView.bounds.size),
            to: nil
        )
        let viewportTop = spotlightViewport.minY - scrollFrame.minY
        let viewportBottom = spotlightViewport.maxY - scrollFrame.minY
        let isVisible = rowTop >= viewportTop && rowBottom <= viewportBottom

        let viewportHeight = max(1, viewportBottom - viewportTop)
        let targetScreenY = viewportTop + viewportHeight * 0.45
        let targetOffset = attributes.frame.midY - targetScreenY

        let minOffset = -scrollView.adjustedContentInset.top
        let maxOffset = max(
            minOffset,
            scrollView.contentSize.height
                - scrollView.bounds.height
                + scrollView.adjustedContentInset.bottom
        )
        let clamped = min(max(targetOffset, minOffset), maxOffset)
        return SpotlightScrollTarget(from: from, to: clamped, isVisible: isVisible)
    }

    /// シートが閉じる動きにつなげて、止まってから行を入れて光らせる（#282）。
    private func runSpotlight(
        _ request: AlarmSpotlightRequest,
        proxy: ScrollViewProxy
    ) async {
        // シートが閉じきる約0.12秒前から動き出す
        try? await Task.sleep(for: .seconds(RowSpotlightTiming.sheetCloseDelay))
        guard !Task.isCancelled else { return }

        let ids = request.alarmIDs
        guard let first = ids.first else { return }

        // List の scrollTo は指定した時間・カーブを使わないため、
        // UIScrollView を CADisplayLink で自分で動かす（#282 レビュー）
        #if DEBUG
        NSLog(
            "%@",
            "[SpotlightScroll] resolve scrollView=\(listScrollView == nil ? "nil" : "ok")"
        )
        #endif
        let measuredFrame = alarmFrameStore.frame(for: first)
        let shouldScroll = RowSpotlightLogic.shouldScroll(
            rowFrame: measuredFrame,
            viewport: spotlightViewport
        )
        var handledByCustomScroll = false
        if let scrollView = listScrollView,
           let target = spotlightScrollTarget(for: first, scrollView: scrollView) {
            handledByCustomScroll = true
            #if DEBUG
            NSLog(
                "%@",
                String(
                    format: "[SpotlightScroll] target from=%.1f to=%.1f visible=%d shouldScroll=%d",
                    Double(target.from),
                    Double(target.to),
                    target.isVisible ? 1 : 0,
                    shouldScroll ? 1 : 0
                )
            )
            #endif
            if shouldScroll {
                let distance = abs(target.to - target.from)
                if reduceMotion {
                    scrollView.setContentOffset(
                        CGPoint(x: scrollView.contentOffset.x, y: target.to),
                        animated: false
                    )
                } else {
                    let duration = RowSpotlightTiming.scrollDuration(for: distance)
                    await withTaskCancellationHandler {
                        await scrollAnimator.animate(
                            scrollView: scrollView,
                            from: target.from,
                            to: target.to,
                            duration: duration
                        )
                    } onCancel: {
                        Task { @MainActor in
                            scrollAnimator.stop()
                        }
                    }
                    guard !Task.isCancelled else { return }
                }
            }
        }

        if !handledByCustomScroll {
            #if DEBUG
            NSLog("%@", "[SpotlightScroll] custom unavailable -> fallback")
            #endif
            // スクロールビューが取れないときだけのフォールバック（位置合わせのみ）
            let frames = ids.compactMap { alarmFrameStore.frame(for: $0) }
            let rowFrame: CGRect? = {
                guard let frame = frames.first else { return nil }
                let minY = frames.map(\.minY).min() ?? frame.minY
                let maxY = frames.map(\.maxY).max() ?? frame.maxY
                return CGRect(x: frame.minX, y: minY, width: frame.width, height: maxY - minY)
            }()
            if RowSpotlightLogic.shouldScroll(
                rowFrame: rowFrame,
                viewport: spotlightViewport
            ) {
                proxy.scrollTo(first, anchor: RowSpotlightTiming.scrollAnchor)
            }
        }

        // スクロールが止まってから行を入れる
        revealedAlarmIDs.formUnion(ids)
        let revealWait = reduceMotion
            ? RowSpotlightTiming.revealOpacity
            : RowSpotlightTiming.revealHeight
        try? await Task.sleep(for: .seconds(revealWait))
        guard !Task.isCancelled else { return }

        // 入り終わってから約0.08秒後に光らせる
        try? await Task.sleep(for: .seconds(RowSpotlightTiming.glowDelayAfterReveal))
        guard !Task.isCancelled else { return }
        spotlightStore.play(ids)

        if let first = ids.first, UIAccessibility.isVoiceOverRunning {
            spotlightFocusedAlarmID = first
        }

        // 光り終わったら、通常の行に戻す
        let glowDuration = RowSpotlightTiming.rise
            + RowSpotlightTiming.hold
            + RowSpotlightTiming.fade
        try? await Task.sleep(for: .seconds(glowDuration + 0.1))
        guard !Task.isCancelled else { return }
        pendingRevealAlarmIDs.subtract(ids)
        revealedAlarmIDs.subtract(ids)
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
        switch PermissionBannerLogic.action(for: status) {
        case .openSettings:
            AnalyticsService.shared.capture(.permissionBannerTapped(
                status: status,
                step: .sheetShown
            ))
            showingPermissionSettings = true
        case .requestAuthorization:
            AnalyticsService.shared.capture(.permissionBannerTapped(status: status))
            Task {
                let granted = await scheduler.requestAuthorization()
                scheduler.refreshPermissionStatus()
                if granted {
                    scheduler.syncAlarms(alarmStore.alarms, trigger: .foreground)
                    permissionFeedbackTrigger += 1
                }
                reportPermissionBannerIfNeeded()
            }
        case nil:
            break
        }
    }

    /// 起動時に一度だけ、既存アラームの音を調べる（#256）。
    private func scanSilentAlarms() {
        guard !didScanSilentAlarms else { return }
        didScanSilentAlarms = true
        let entries = alarmStore.alarms
        let directory = AudioConverter.shared.soundsDirectory
        let cached = AppGroup.silentAlarmScanCache
        Task.detached {
            let result = SilentAlarmScanner.scan(
                entries: entries,
                soundsDirectory: directory,
                cached: cached,
                measure: { LoudnessMeter.measure(fileURL: $0) }
            )
            await MainActor.run {
                // 測った結果は次回起動のために残す（#256 レビュー）
                AppGroup.silentAlarmScanCache = result.cache
                silentAlarmLevels = result.levels
            }
        }
    }

    private func repairSilentAlarm(
        _ alarm: AlarmEntry,
        sound: AlarmSound?,
        playlistID: UUID?
    ) {
        guard var updated = alarmStore.alarms.first(where: { $0.id == alarm.id }) else {
            fixingSilentAlarm = nil
            return
        }
        if let sound {
            updated.soundFileName = sound.fileName
            updated.playlistID = nil
        } else if let playlistID {
            updated.soundFileName = ""
            updated.playlistID = playlistID
        }
        alarmStore.update(updated)
        AlarmScheduler.shared.syncAlarms(alarmStore.alarms, trigger: .edit)
        if let level = silentAlarmLevels.removeValue(forKey: alarm.id) {
            AnalyticsService.shared.capture(.silentSoundBlocked(
                level: level,
                source: .existing,
                action: .fixedExisting
            ))
        }
        fixingSilentAlarm = nil
    }

    // MARK: - First alarm follow-up (#247)

    /// 起動時に一度だけ、初めての1回きりアラームの提案を出すか決める。
    /// 許可の行 → プレイリストの解放 → この提案、の順で1つだけ出す。
    private func evaluateFirstAlarmFollowup() {
        guard !AppGroup.firstAlarmFollowupHandled else { return }

        // 前回の起動で表示したまま閉じられた（強制終了を含む）＝無視。
        if AppGroup.firstAlarmFollowupShown {
            AppGroup.firstAlarmFollowupHandled = true
            AppGroup.firstAlarmFollowupShown = false
            AnalyticsService.shared.capture(.firstAlarmFollowupAction(action: .ignored))
            return
        }

        let unlockWouldShow = PlaylistUnlockLogic.canPresent(
            hasPending: soundStore.hasPendingPlaylistUnlock,
            hasShown: AppGroup.playlistUnlockShown,
            isRinging: scheduler.isAlarmRinging,
            isNightMode: BedsideModeTracker.shared.isActive,
            hasAnotherSheet: false
        )
        guard FirstAlarmFollowupLogic.shouldShow(
            hasPermissionBanner: permissionBannerStatus != nil,
            unlockWouldShow: unlockWouldShow
        ) else { return }
        guard !addScreenVisible,
              !editScreenVisible,
              !showingSettings,
              !showingOnboarding,
              shareImportItem == nil,
              updateChecker.prompt == nil else { return }

        // 履歴（1.8.3 以降）が入れたときから揃っている人だけ（#247 レビュー）
        guard FirstAlarmFollowupLogic.isFirstInstallVersionEligible(
            AppGroup.firstInstallVersion
        ) else { return }

        let history = AlarmLocalHistoryStore.recentLines(
            limit: AlarmLocalHistoryStore.maxLines
        )
        let candidate = FirstAlarmFollowupLogic.candidate(
            historyLines: history,
            alarms: alarmStore.alarms,
            uidForAlarm: { AlarmUIDStore.uid(for: $0) }
        )
        switch FirstAlarmFollowupLogic.eligibility(
            candidate: candidate,
            alarms: alarmStore.alarms
        ) {
        case let .offer(alarmID):
            firstAlarmFollowupAlarmID = alarmID
            AppGroup.firstAlarmFollowupShown = true
            AnalyticsService.shared.capture(.firstAlarmFollowupShown)
        case .changedOrRemoved, .tooOld:
            // 自分でオン・繰り返しにした／古すぎる。提案は出さず、以後も出さない。
            // ユーザーの操作を「無視」として送らない。
            AppGroup.firstAlarmFollowupHandled = true
        case .none:
            break
        }
    }

    private func applyFirstAlarmFollowup(
        _ action: FirstAlarmFollowupAction,
        to alarm: AlarmEntry
    ) {
        guard var updated = alarmStore.alarms.first(where: { $0.id == alarm.id }),
              let changed = FirstAlarmFollowupLogic.updatedAlarm(updated, for: action)
        else { return }
        updated = changed
        alarmStore.update(updated)
        AlarmScheduler.shared.syncAlarms(alarmStore.alarms, trigger: .edit)
        refreshGlobalSkip()

        firstAlarmFollowupAlarmID = nil
        AppGroup.firstAlarmFollowupHandled = true
        AppGroup.firstAlarmFollowupShown = false
        AnalyticsService.shared.capture(.firstAlarmFollowupAction(action: action))
    }

    /// 押さずに一覧を離れたとき（設定・追加・編集・バックグラウンド）。
    private func ignoreFirstAlarmFollowupIfNeeded() {
        guard firstAlarmFollowupAlarmID != nil else { return }
        firstAlarmFollowupAlarmID = nil
        AppGroup.firstAlarmFollowupHandled = true
        AppGroup.firstAlarmFollowupShown = false
        AnalyticsService.shared.capture(.firstAlarmFollowupAction(action: .ignored))
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
    let hasSilentSound: Bool
    let showsFirstAlarmFollowup: Bool
    /// 作った・時刻を変えた行を一度だけ光らせる（#282）
    let spotlight: RowSpotlightController
    /// VoiceOver のフォーカスを移す（#282）
    let spotlightFocus: AccessibilityFocusState<UUID?>.Binding
    let onFixSilentSound: () -> Void
    let onFirstAlarmFollowup: (FirstAlarmFollowupAction) -> Void
    let onToggle: () -> Void
    let onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: hasSilentSound ? onFixSilentSound : onTap) {
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
            .accessibilityFocused(spotlightFocus, equals: alarm.id)

            // 初めての1回きりアラームのあとの提案（#247）。押すまで何も変えない。
            if showsFirstAlarmFollowup {
                followupButtons
            }
        }
    }

    // MARK: - First alarm follow-up (#247)

    @ViewBuilder
    private var followupButtons: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                followupButton(.tomorrow)
                followupButton(.weekdays)
                followupButton(.everyday)
            }
        } else {
            HStack(spacing: 8) {
                followupButton(.tomorrow)
                followupButton(.weekdays)
                followupButton(.everyday)
            }
        }
    }

    private func followupButton(_ action: FirstAlarmFollowupAction) -> some View {
        Button {
            onFirstAlarmFollowup(action)
        } label: {
            Text(followupTitle(action))
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.bordered)
        .tint(Color.actionText)
        .accessibilityIdentifier("alarm.followup.\(action.rawValue)")
    }

    private func followupTitle(_ action: FirstAlarmFollowupAction) -> LocalizedStringKey {
        switch action {
        case .tomorrow: "followup_tomorrow"
        case .weekdays: "followup_weekdays"
        case .everyday: "followup_everyday"
        case .ignored: "followup_tomorrow"
        }
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
                if hasSilentSound { silentSoundWarning }
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
            if hasSilentSound { silentSoundWarning }
            if let holidaySummary {
                Text(holidaySummary)
                    .font(.caption)
                    .foregroundStyle(metaColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("holiday.summary")
            }
        }
    }

    private var silentSoundWarning: some View {
        Text("silent_alarm_warning")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("alarm.silentSoundWarning")
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
        .accessibilityIdentifier("alarm.toggle")
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
