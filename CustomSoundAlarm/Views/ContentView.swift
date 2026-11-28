import SwiftUI
import StoreKit
import UIKit
import Accessibility

/// 追加画面への要求（sheet(item:) 用・#101）
struct AddAlarmRequest: Identifiable {
    let id = UUID()
    let source: OnboardingSource?
    let initialSound: AlarmSound?
    /// プレイリストを作った直後に、そのプレイリストを選んだ状態で開く（#324）
    let initialPlaylistID: UUID?

    init(
        source: OnboardingSource?,
        initialSound: AlarmSound? = nil,
        initialPlaylistID: UUID? = nil
    ) {
        self.source = source
        self.initialSound = initialSound
        self.initialPlaylistID = initialPlaylistID
    }
}

/// 保存したときに、どの行へ何の1文を出すか（#289）。
private struct PendingUntilRing: Equatable {
    let alarmID: UUID
    let message: String
}

/// 一覧で行を入れて光らせる要求（#282 / #198）。
private struct AlarmSpotlightRequest: Equatable {
    let token = UUID()
    let alarmIDs: [UUID]
    /// スクロールを始める位置（保存したときの一覧の位置）
    let startOffset: CGFloat
    /// スクロールが止まってから行を入れる（上・中に入る場合）
    let insertAfterScroll: Bool
    /// 画面内に入る最後の行を、その場で開いて見せる（短い一覧・#282 レビュー）
    let revealInPlace: Bool
    /// 光るときに、次に鳴るまでの1文も出す（#289）
    let untilRing: PendingUntilRing?
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
    /// 一覧の行に数秒だけ出す、次に鳴るまでの1文（#289）
    @State private var untilRingNotice = UntilRingNoticeController()
    /// この保存で出す1文と行（#289）
    @State private var pendingUntilRing: PendingUntilRing?
    /// シートが閉じるまで一覧に出さない行（#282 レビュー）
    @State private var hiddenUntilDismissAlarmIDs: Set<UUID> = []
    /// 開く前の中身の自然な高さ（#282 レビュー）
    @State private var measuredRevealHeights: [UUID: CGFloat] = [:]
    /// すき間が開ききって、カードと中身を出した行（#282 レビュー）
    @State private var shownRevealAlarmIDs: Set<UUID> = []
    /// シートが閉じたら演出を始める行（#282 レビュー）
    @State private var pendingSpotlightAlarmIDs: Set<UUID> = []
    /// 保存したときの一覧の位置（#282 レビュー）
    @State private var pendingSpotlightStartOffset: CGFloat?
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
    /// 作ったあとに使うアラームを選ぶ（#324）
    @State private var apply = PlaylistApplyCoordinator.shared
    /// 許可状態（#230）
    @State private var scheduler = AlarmScheduler.shared
    /// 追加・編集画面が実際に開いているか（sheet の item より確実・#216）
    @State private var addScreenVisible = false
    @State private var editScreenVisible = false
    /// すべてのアラームを休む（#197 画面作り直し）
    @State private var showingSkipAll = false
    /// 起動直後から止まっていた行を、動かさずにそのまま見せる（#296）。
    @State private var globalSkip: GlobalSkip? = AppGroup.globalSkip
    /// 一覧の上に出す帯のデータ（#296 実機確認）。閉じ終わるまで残す。
    @State private var noticeSkip: GlobalSkip? = AppGroup.globalSkip
    /// 帯を開いているか。0 のときは高さも 0。
    @State private var noticeOpen = AppGroup.globalSkip?.isActive == true
    /// 帯の自然な高さ。開く前に測ってから高さを動かす。
    @State private var noticeHeight: CGFloat = 0
    @State private var pendingNoticeOpen = false
    @State private var noticeCloseTask: Task<Void, Never>?
    /// 帯が開ききるまで、行の層とアイコンを待たせる（#296 実機確認）。
    @State private var pausedEntryDelay: TimeInterval = 0
    /// 許可バナーの表示済み計測（#230）
    @State private var reportedPermissionBannerStatus: AlarmPermissionStatus?
    /// 設定アプリへ移る前のシート（#239）
    @State private var showingPermissionSettings = false
    /// 許可がオンになったときの触覚（#239）
    @State private var permissionFeedbackTrigger = 0
    @State private var skipToast: String?
    @State private var skipToastTask: Task<Void, Never>?
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
                    // 既存の人（2曲以上・プレイリストなし・未表示）にも1回だけ出す（#280）
                    schedulePlaylistUnlockAttempt()
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
                startPendingSpotlight()
            }) { request in
                AlarmDetailView(
                    mode: .add,
                    initialImport: request.source,
                    initialSound: request.initialSound,
                    initialPlaylistID: request.initialPlaylistID,
                    onClose: {
                        addScreenVisible = false
                        addAlarmRequest = nil
                        schedulePlaylistUnlockAttempt()
                    },
                    onSaved: { saved, shouldSpotlight, shouldAnnounce in
                        handleAlarmSaved(
                            saved,
                            shouldSpotlight: shouldSpotlight,
                            shouldAnnounce: shouldAnnounce
                        )
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
                startPendingSpotlight()
            }) { alarm in
                AlarmDetailView(
                    mode: .edit(alarm),
                    onClose: {
                        editScreenVisible = false
                        selectedAlarm = nil
                        schedulePlaylistUnlockAttempt()
                    },
                    onSaved: { saved, shouldSpotlight, shouldAnnounce in
                        handleAlarmSaved(
                            saved,
                            shouldSpotlight: shouldSpotlight,
                            shouldAnnounce: shouldAnnounce
                        )
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
        .animation(.easeInOut(duration: 0.25), value: skipToast)
        .sensoryFeedback(.success, trigger: permissionFeedbackTrigger)
        .sensoryFeedback(.success, trigger: quickSaveFeedbackTrigger)
        .onChange(of: soundStore.hasPendingPlaylistUnlock) { _, hasPending in
            if hasPending { schedulePlaylistUnlockAttempt() }
        }
        .onChange(of: apply.pendingAddAlarmPlaylistID) { _, playlistID in
            guard playlistID != nil else { return }
            openAddAlarmForPlaylistApply()
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
            if !isShowing {
                schedulePlaylistUnlockAttempt()
                presentNextShareImportIfNeeded()
            }
        }
        .onChange(of: addAlarmRequest == nil) { _, isClosed in
            if isClosed { presentNextShareImportIfNeeded() }
        }
        .onChange(of: selectedAlarm == nil) { _, isClosed in
            if isClosed { presentNextShareImportIfNeeded() }
        }
        .onChange(of: updateChecker.prompt == nil) { _, isClosed in
            if isClosed {
                schedulePlaylistUnlockAttempt()
                presentNextShareImportIfNeeded()
            }
        }
        .onChange(of: permissionBannerStatus) { _, status in
            // 許可の1行が消えたら、次の提案（解放）に進む（#280）
            if status == nil { schedulePlaylistUnlockAttempt() }
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

    /// アラームが0本のとき、作ったプレイリストを選んだ状態で追加画面を開く（#324）。
    private func openAddAlarmForPlaylistApply() {
        guard let playlistID = apply.takePendingAddAlarmPlaylistID() else { return }
        addScreenVisible = true
        addAlarmRequest = AddAlarmRequest(source: nil, initialPlaylistID: playlistID)
    }

    /// 端末内の履歴に鳴った記録があるか（#324）。
    private func hasAlarmFired() -> Bool {
        FirstAlarmFollowupLogic.hasFiredAlarm(
            historyLines: AlarmLocalHistoryStore.recentLines(
                limit: AlarmLocalHistoryStore.maxLines
            )
        )
    }

    private func attemptPlaylistUnlock() {
        guard !addScreenVisible,
              !editScreenVisible,
              !showingSettings,
              !showingOnboarding,
              !showingPermissionSettings,
              !showingSkipAll,
              shareImportItem == nil,
              fixingSilentAlarm == nil,
              updateChecker.prompt == nil,
              !AppGroup.playlistUnlockShown else { return }
        // 起動時に既存の人へ出すときは、許可の1行を先に出す（#280）。
        // 2つ目の取り込みの直後は、取り込みの文脈を優先して出す（#216）。
        let trigger = PlaylistUnlockLogic.trigger(
            hasPending: soundStore.hasPendingPlaylistUnlock,
            hasFiredAlarm: hasAlarmFired(),
            customSoundCount: soundStore.customSoundCount,
            playlistCount: PlaylistStore.shared.playlists.count,
            hasShown: AppGroup.playlistUnlockShown
        )
        if trigger == .existingUser, permissionBannerStatus != nil { return }
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

        // 作った直後も、一覧の上に次に鳴るまでの1文を出す（#289）
        showUntilRing(for: entry)

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

    /// 次に鳴るまでの1文を、その行に数秒だけ出す（#289）。
    private func showUntilRing(for entry: AlarmEntry) {
        guard let message = NextRingAnnouncement.message(for: entry) else { return }
        untilRingNotice.show(message, for: entry.id)
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
        let next = AppGroup.globalSkip
        let previous = activeGlobalSkip

        // 再開：行だけ先に戻し、戻りきってから帯を閉じる（#296 実機確認）。
        if let previous, next?.isActive != true {
            noticeCloseTask?.cancel()
            globalSkip = next
            guard !reduceMotion else {
                closeNoticeNow()
                return
            }
            noticeSkip = previous
            scheduleNoticeClose()
            return
        }

        // 休みに入った：帯を先に開き、一覧が下がりきってから行を動かす（#296 実機確認）。
        if let next, next.isActive, previous == nil {
            noticeCloseTask?.cancel()
            pausedEntryDelay = reduceMotion
                ? 0
                : PausedRowTiming.noticeIn + PausedRowTiming.noticeSettle
            globalSkip = next
            openNotice(next)
            return
        }

        globalSkip = next
    }

    /// 帯を開く。高さを測ってから 0.3 秒で開き、一覧を下げる（#296 実機確認）。
    private func openNotice(_ skip: GlobalSkip) {
        noticeSkip = skip
        guard !reduceMotion else {
            noticeOpen = true
            return
        }
        if noticeHeight > 0 {
            withAnimation(.timingCurve(0.05, 0.7, 0.1, 1, duration: PausedRowTiming.noticeIn)) {
                noticeOpen = true
            }
            return
        }
        noticeOpen = false
        pendingNoticeOpen = true
    }

    /// 行が戻りきってから、帯を閉じる（#296 実機確認）。
    private func scheduleNoticeClose() {
        noticeCloseTask?.cancel()
        guard let skip = noticeSkip else { return }
        let pausedCount = displayedAlarms.filter {
            AlarmSkipLogic.globalSkipRowEnd(for: $0, globalSkip: skip) != nil
        }.count
        let delay = PausedRowTiming.noticeCloseDelay(pausedCount: pausedCount)
        noticeCloseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: PausedRowTiming.noticeOut)) {
                noticeOpen = false
            }
            try? await Task.sleep(for: .seconds(PausedRowTiming.noticeOut))
            guard !Task.isCancelled else { return }
            noticeSkip = nil
        }
    }

    /// Reduce Motion では帯も行と同時に消す（#296 実機確認）。
    private func closeNoticeNow() {
        noticeCloseTask?.cancel()
        noticeOpen = false
        noticeSkip = nil
    }

    /// 帯の高さ。開いていてまだ測れていなければ、自然な高さに任せる。
    private var noticeFrameHeight: CGFloat? {
        guard noticeOpen else { return 0 }
        return noticeHeight > 0 ? noticeHeight : nil
    }

    /// 帯の自然な高さを測り、準備ができていたら 0.3 秒で開く（#296 実機確認）。
    private func measureNotice(_ height: CGFloat) {
        guard height > 0, abs(height - noticeHeight) > 0.5 else { return }
        noticeHeight = height
        guard pendingNoticeOpen else { return }
        pendingNoticeOpen = false
        withAnimation(.timingCurve(0.05, 0.7, 0.1, 1, duration: PausedRowTiming.noticeIn)) {
            noticeOpen = true
        }
    }

    /// 上から何番目に止まっている行か（層と線を 0.08 秒ずつずらす・#296）。
    private func pausedRowIndex(for alarmID: UUID) -> Int {
        // 再開のときも、戻る順番が変わらないように控えの帯を使う。
        guard let skip = activeGlobalSkip ?? noticeSkip,
              let index = displayedAlarms.firstIndex(where: { $0.id == alarmID })
        else { return 0 }
        return displayedAlarms[..<index].filter {
            AlarmSkipLogic.globalSkipRowEnd(for: $0, globalSkip: skip) != nil
        }.count
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
        let visible = alarmStore.alarms.filter {
            !hiddenUntilDismissAlarmIDs.contains($0.id)
        }
        let sorted = AlarmListOrdering.sortedForDisplay(visible)
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
                if let skip = noticeSkip {
                    GlobalSkipNoticeRow(
                        skip: skip,
                        entries: alarmStore.alarms,
                        onResume: {
                            AlarmSkipService.undoAll()
                            refreshGlobalSkip()
                        }
                    )
                    .opacity(noticeOpen ? 1 : 0)
                    .frame(height: noticeFrameHeight, alignment: .top)
                    .clipped()
                    .allowsHitTesting(noticeOpen)
                    .accessibilityHidden(!noticeOpen)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .background(alignment: .top) {
                        // 開く前に、閉じたまま同じ幅で自然な高さを測る。
                        GlobalSkipNoticeRow(
                            skip: skip,
                            entries: alarmStore.alarms,
                            onResume: {}
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            measureNotice(height)
                        }
                    }
                }
                ForEach(displayedAlarms, id: \.id) { alarm in
                    Group {
                        if pendingRevealAlarmIDs.contains(alarm.id) {
                            SpotlightRevealRow(
                                isRevealed: revealedAlarmIDs.contains(alarm.id),
                                isShown: shownRevealAlarmIDs.contains(alarm.id),
                                reduceMotion: reduceMotion,
                                onMeasured: { height in
                                    guard abs(
                                        (measuredRevealHeights[alarm.id] ?? 0) - height
                                    ) > 0.5 else { return }
                                    measuredRevealHeights[alarm.id] = height
                                }
                            ) {
                                alarmRowContent(alarm)
                            }
                        } else {
                            alarmRowContent(alarm)
                        }
                    }
                    .warmCard(
                        spotlight: spotlightStore.controller(for: alarm.id),
                        revealOpacity: pendingRevealAlarmIDs.contains(alarm.id)
                            ? (shownRevealAlarmIDs.contains(alarm.id) ? 1 : 0)
                            : 1
                    )
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
            .warmListBackground()
            // 先頭の行がナビゲーションバーのぼかしに重ならないための上端の余白
            .contentMargins(
                .top,
                RowSpotlightTiming.minimumVisibleInset,
                for: .scrollContent
            )
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
                SkipAllSheet(
                    entries: alarmStore.alarms.filter(\.isEnabled),
                    hasActiveSkip: activeGlobalSkip != nil
                )
            }
        }
    }

    // MARK: - Row spotlight (#282)

    /// 一覧の1行（スポットライトの対象でも同じ中身を使う）。
    private func alarmRowContent(_ alarm: AlarmEntry) -> some View {
        let pausedUntil = activeGlobalSkip.flatMap {
            AlarmSkipLogic.globalSkipRowEnd(for: alarm, globalSkip: $0)
        }
        return AlarmRow(
            alarm: alarm,
            soundName: AlarmSoundDisplay.name(for: alarm),
            sound: AlarmSoundDisplay.representativeSound(for: alarm),
            hasSilentSound: silentAlarmLevels[alarm.id] != nil,
            showsFirstAlarmFollowup: firstAlarmFollowupAlarmID == alarm.id,
            spotlight: spotlightStore.controller(for: alarm.id),
            spotlightFocus: $spotlightFocusedAlarmID,
            untilRingNotice: untilRingNotice,
            pausedUntil: pausedUntil,
            pausedIndex: pausedRowIndex(for: alarm.id),
            pausedEntryDelay: pausedEntryDelay,
            onPausedTap: { showingSkipAll = true },
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
                let turningOn = !alarm.isEnabled
                alarmStore.toggleEnabled(alarm)
                AlarmScheduler.shared.syncAlarms(alarmStore.alarms, trigger: .edit)
                refreshGlobalSkip()
                // オンにしたときは、次に鳴るまでの1文をその場で出す（#289）
                if turningOn,
                   let updated = alarmStore.alarms.first(where: { $0.id == alarm.id }) {
                    showUntilRing(for: updated)
                }
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

    /// 保存された行を、シートが閉じるまで一覧に出さない（#282 レビュー）。
    /// 保存から `onDismiss` のあいだに contentOffset が動かないようにする。
    /// 次に鳴るまでの1文は、光るときまで持ち越す（#289）。
    private func handleAlarmSaved(
        _ alarm: AlarmEntry,
        shouldSpotlight: Bool,
        shouldAnnounce: Bool
    ) {
        pendingUntilRing = nil
        if shouldAnnounce,
           let message = NextRingAnnouncement.message(for: alarm) {
            pendingUntilRing = PendingUntilRing(
                alarmID: alarm.id,
                message: message
            )
        }

        guard shouldSpotlight else { return }

        pendingSpotlightStartOffset = listScrollView?.contentOffset.y
        hiddenUntilDismissAlarmIDs.insert(alarm.id)
        measuredRevealHeights.removeValue(forKey: alarm.id)
        shownRevealAlarmIDs.remove(alarm.id)
        pendingSpotlightAlarmIDs.insert(alarm.id)
        syncDisplayedAlarms()
        #if DEBUG
        NSLog(
            "%@",
            String(
                format: "[SpotlightScroll] saved offset=%.1f hidden=%d",
                Double(listScrollView?.contentOffset.y ?? .nan),
                hiddenUntilDismissAlarmIDs.count
            )
        )
        #endif
    }

    /// シートが閉じきってから、行を入れてスクロール・光り方を始める（#282 レビュー）。
    private func startPendingSpotlight() {
        let untilRing = pendingUntilRing
        pendingUntilRing = nil

        guard !pendingSpotlightAlarmIDs.isEmpty else {
            // 行を光らせない保存（曜日・休みだけ変えたとき）でも1文は出す（#289）
            if let untilRing {
                untilRingNotice.show(untilRing.message, for: untilRing.alarmID)
            }
            return
        }
        let ids = Array(pendingSpotlightAlarmIDs)
        pendingSpotlightAlarmIDs.removeAll()
        let startOffset = pendingSpotlightStartOffset
            ?? listScrollView?.contentOffset.y
            ?? 0
        pendingSpotlightStartOffset = nil

        // 上・中に入る行はスクロールが止まるまで一覧に足さない（下に入る行だけ先に入れる）
        let sorted = AlarmListOrdering.sortedForDisplay(alarmStore.alarms)
        let firstID = ids[0]
        let fullIndex = sorted.firstIndex(where: { $0.id == firstID }) ?? sorted.count
        let visibleBefore = sorted[..<fullIndex].filter {
            !hiddenUntilDismissAlarmIDs.contains($0.id)
        }.count
        let insertAfterScroll = visibleBefore < displayedAlarms.count

        // 一番下に入る行が、今の位置のまま画面内に収まるか（短い一覧・#282 レビュー）。
        // 収まるなら開く動きを見せ、収まらないなら今までどおり一覧の一番下へ送る。
        var revealInPlace = false
        if !insertAfterScroll,
           let scrollView = listScrollView,
           let last = displayedAlarms.last,
           let lastFrame = alarmFrameStore.frame(for: last.id) {
            let visibleBottomScreen = scrollView.convert(
                CGPoint(
                    x: 0,
                    y: scrollView.bounds.height - scrollView.adjustedContentInset.bottom
                ),
                to: nil
            ).y
            let newRowHeight = max(lastFrame.height, 96)
            revealInPlace = lastFrame.maxY + newRowHeight
                + RowSpotlightTiming.minimumVisibleInset <= visibleBottomScreen + 0.5
        }

        // 前の演出が残っていたら、その行は出し切ってから次へ
        if !pendingRevealAlarmIDs.isEmpty {
            revealedAlarmIDs.formUnion(pendingRevealAlarmIDs)
            pendingRevealAlarmIDs.removeAll()
        }

        if insertAfterScroll {
            // まだ一覧に足さない。スクロール後に insertRowsAfterScroll で入れる
        } else if revealInPlace {
            // 画面内に入る行は collapsed で足して、スクロールせずに開く動きを見せる
            hiddenUntilDismissAlarmIDs.subtract(ids)
            pendingRevealAlarmIDs.formUnion(ids)
            revealedAlarmIDs.subtract(ids)
            syncDisplayedAlarms()
        } else {
            // 画面外に入る行は、一覧の一番下まで送るため先に通常の行として入れる
            // （画面外なので、開く動きは見えない。光りはスクロール後に付ける）
            hiddenUntilDismissAlarmIDs.subtract(ids)
            pendingRevealAlarmIDs.subtract(ids)
            revealedAlarmIDs.subtract(ids)
            syncDisplayedAlarms()
        }

        #if DEBUG
        NSLog(
            "%@",
            String(
                format: "[SpotlightScroll] dismiss offset=%.1f ids=%d visibleBefore=%d shown=%d mode=%@",
                Double(listScrollView?.contentOffset.y ?? .nan),
                ids.count,
                visibleBefore,
                displayedAlarms.count,
                insertAfterScroll
                    ? "after-scroll"
                    : (revealInPlace ? "bottom-reveal" : "bottom-now")
            )
        )
        #endif
        spotlightRequest = AlarmSpotlightRequest(
            alarmIDs: ids,
            startOffset: startOffset,
            insertAfterScroll: insertAfterScroll,
            revealInPlace: revealInPlace,
            untilRing: untilRing
        )
    }

    /// スクロールが止まったあとで、上・中に入る行を collapsed で足す（#282 レビュー）。
    private func insertRowsAfterScroll(_ ids: [UUID]) {
        guard let scrollView = listScrollView else { return }
        let offsetBeforeInsert = scrollView.contentOffset.y
        ids.forEach { measuredRevealHeights.removeValue(forKey: $0) }
        shownRevealAlarmIDs.subtract(ids)
        hiddenUntilDismissAlarmIDs.subtract(ids)
        pendingRevealAlarmIDs.formUnion(ids)
        revealedAlarmIDs.subtract(ids)
        syncDisplayedAlarms()
        if let collectionView = scrollView as? UICollectionView {
            collectionView.layoutIfNeeded()
        }
        // 行の挿入で一覧が自分で offset を動かしても、見えている位置を変えない
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: offsetBeforeInsert),
            animated: false
        )
        #if DEBUG
        NSLog(
            "%@",
            String(
                format: "[SpotlightScroll] inserted offset=%.1f (kept %.1f)",
                Double(scrollView.contentOffset.y),
                Double(offsetBeforeInsert)
            )
        )
        #endif
    }

    /// 行が「見えるところまで最小限」になるスクロール位置を求める（#282 レビュー）。
    /// `scrollRectToVisible` と同じ考え方で、上下のバーに隠れる部分は見えていないとみなす。
    /// - Parameter rowIsInserted: false のときは、まだ一覧に足していない行の入る位置を
    ///   次の行（または最後の行の下端）から求める。
    private func spotlightScrollTarget(
        for alarmID: UUID,
        scrollView: UIScrollView,
        startOffset: CGFloat,
        rowIsInserted: Bool
    ) -> SpotlightScrollTarget? {
        guard spotlightViewport.height > 0,
              let collectionView = scrollView as? UICollectionView
        else { return nil }

        // 上に許可バナー・全体の休みの行があれば、その分だけ indexPath をずらす
        let leadingRows = (permissionBannerStatus != nil ? 1 : 0)
            + (activeGlobalSkip != nil ? 1 : 0)

        // 追加直後は行のレイアウトが古いことがあるため、一度整えてから読む。
        // その前後で contentOffset が飛んでいないかを DEBUG ログで確認する。
        let offsetBeforeLayout = scrollView.contentOffset.y
        #if DEBUG
        NSLog(
            "%@",
            String(
                format: "[SpotlightScroll] layout before offset=%.1f",
                Double(offsetBeforeLayout)
            )
        )
        #endif
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.layoutIfNeeded()
        let offsetAfterLayout = scrollView.contentOffset.y
        #if DEBUG
        NSLog(
            "%@",
            String(
                format: "[SpotlightScroll] layout after offset=%.1f",
                Double(offsetAfterLayout)
            )
        )
        #endif
        if abs(offsetAfterLayout - startOffset) > 0.5 {
            // レイアウト更新で位置が飛んだら、保存したときの位置に戻す
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: startOffset),
                animated: false
            )
            #if DEBUG
            NSLog(
                "%@",
                String(
                    format: "[SpotlightScroll] offset restored to %.1f",
                    Double(startOffset)
                )
            )
            #endif
        }

        let from = startOffset
        let sorted = AlarmListOrdering.sortedForDisplay(alarmStore.alarms)
        let fullIndex = sorted.firstIndex(where: { $0.id == alarmID }) ?? sorted.count
        let fullCount = sorted.count

        // 最後の行は一度だけ画面内まで送って高さを確定させ、contentSize を更新する。
        // すぐ元の位置に戻すので、画面上には出ない（プローブ）。
        if fullIndex == fullCount - 1,
           rowIsInserted,
           let index = displayedAlarms.firstIndex(where: { $0.id == alarmID }) {
            let probeIndexPath = IndexPath(row: leadingRows + index, section: 0)
            collectionView.scrollToItem(at: probeIndexPath, at: .bottom, animated: false)
            collectionView.layoutIfNeeded()
            #if DEBUG
            NSLog(
                "%@",
                String(
                    format: "[SpotlightScroll] probe offset=%.1f size=%.1f",
                    Double(scrollView.contentOffset.y),
                    Double(collectionView.contentSize.height)
                )
            )
            #endif
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: startOffset),
                animated: false
            )
        }

        let rowTop: CGFloat
        let rowHeight: CGFloat

        if rowIsInserted,
           let index = displayedAlarms.firstIndex(where: { $0.id == alarmID }) {
            let indexPath = IndexPath(row: leadingRows + index, section: 0)
            guard let attributes = collectionView.layoutAttributesForItem(at: indexPath)
                ?? collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)
            else { return nil }
            rowTop = attributes.frame.minY
            rowHeight = alarmFrameStore.frame(for: alarmID)?.height
                ?? max(attributes.frame.height, 96)
        } else {
            // まだ足していない行の入る位置：次の可視行の上端、なければ最後の行の下端
            let visibleBefore = sorted[..<fullIndex].filter {
                !hiddenUntilDismissAlarmIDs.contains($0.id)
            }.count

            if visibleBefore < displayedAlarms.count {
                let indexPath = IndexPath(row: leadingRows + visibleBefore, section: 0)
                guard let attributes = collectionView.layoutAttributesForItem(at: indexPath)
                    ?? collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)
                else { return nil }
                rowTop = attributes.frame.minY
                rowHeight = max(attributes.frame.height, 96)
            } else if let last = displayedAlarms.last,
                      let index = displayedAlarms.firstIndex(where: { $0.id == last.id }) {
                let indexPath = IndexPath(row: leadingRows + index, section: 0)
                guard let attributes = collectionView.layoutAttributesForItem(at: indexPath)
                    ?? collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)
                else { return nil }
                rowTop = attributes.frame.maxY
                rowHeight = max(attributes.frame.height, 96)
            } else {
                rowTop = -scrollView.adjustedContentInset.top
                rowHeight = 96
            }
        }

        let rowBottom = rowTop + rowHeight
        // UIScrollView から見えている内容範囲を出す（バー・広告枠は adjustedContentInset）
        let visibleTopContent = from + scrollView.adjustedContentInset.top
        let visibleBottomContent = from + scrollView.bounds.height
            - scrollView.adjustedContentInset.bottom
        let rowTopScreen = rowTop - from
        let rowBottomScreen = rowBottom - from
        let inset = RowSpotlightTiming.minimumVisibleInset

        var reason = "visible"
        var targetOffset = from
        if fullIndex == 0 {
            // 先頭の行は一覧の一番上（大見出しが出る自然な位置）まで
            reason = "top-edge"
            targetOffset = -scrollView.adjustedContentInset.top
        } else if fullIndex == fullCount - 1 {
            // 最後の行は一覧の一番下まで
            reason = "bottom-edge"
            targetOffset = scrollView.contentSize.height
                + scrollView.adjustedContentInset.bottom
                - scrollView.bounds.height
        } else if rowTop < visibleTopContent + inset {
            reason = "above"
            targetOffset = rowTop
                - scrollView.adjustedContentInset.top
                - inset
        } else if rowBottom > visibleBottomContent - inset {
            reason = "below"
            targetOffset = rowBottom
                - (scrollView.bounds.height - scrollView.adjustedContentInset.bottom - inset)
        }
        let isVisible = reason == "visible"

        let minOffset = -scrollView.adjustedContentInset.top
        let maxOffset = max(
            minOffset,
            scrollView.contentSize.height
                - scrollView.bounds.height
                + scrollView.adjustedContentInset.bottom
        )
        let clamped = min(max(targetOffset, minOffset), maxOffset)

        #if DEBUG
        NSLog(
            "%@",
            String(
                format: "[SpotlightScroll] target reason=%@ inserted=%d from=%.1f to=%.1f rowScreen=%.1f...%.1f visibleContent=%.1f...%.1f inset=%.1f/%.1f size=%.1f bounds=%.1f",
                reason,
                rowIsInserted ? 1 : 0,
                Double(from),
                Double(clamped),
                Double(rowTopScreen),
                Double(rowBottomScreen),
                Double(visibleTopContent),
                Double(visibleBottomContent),
                Double(scrollView.adjustedContentInset.top),
                Double(scrollView.adjustedContentInset.bottom),
                Double(collectionView.contentSize.height),
                Double(scrollView.bounds.height)
            )
        )
        #endif
        return SpotlightScrollTarget(from: from, to: clamped, isVisible: isVisible)
    }

    /// 開く行の中身の自然な高さが測れるまで待つ（#282 レビュー）。
    /// 測れる前に `revealed` にすると、高さ0から自然な高さへ跳んでしまう。
    private func waitForRevealMeasurement(
        _ ids: [UUID],
        timeout: TimeInterval = 0.5
    ) async {
        let started = Date()
        while !ids.allSatisfy({ (measuredRevealHeights[$0] ?? 0) > 0 }) {
            if Date().timeIntervalSince(started) >= timeout { break }
            try? await Task.sleep(for: .milliseconds(8))
            if Task.isCancelled { return }
        }
        #if DEBUG
        let heights = ids
            .map { String(format: "%.1f", measuredRevealHeights[$0] ?? 0) }
            .joined(separator: ",")
        NSLog(
            "%@",
            String(
                format: "[SpotlightReveal] measured heights=%@ waited=%.0fms",
                heights,
                Date().timeIntervalSince(started) * 1000
            )
        )
        #endif
    }

    /// シートが閉じる動きにつなげて、止まってから行を入れて光らせる（#282）。
    private func runSpotlight(
        _ request: AlarmSpotlightRequest,
        proxy: ScrollViewProxy
    ) async {
        let ids = request.alarmIDs
        guard let first = ids.first else { return }

        // シートが閉じきった直後から動き出す（閉じる動きには重ねない）
        #if DEBUG
        NSLog(
            "%@",
            String(
                format: "[SpotlightScroll] start offset=%.1f wanted=%.1f scrollView=%@ mode=%@",
                Double(listScrollView?.contentOffset.y ?? .nan),
                Double(request.startOffset),
                listScrollView == nil ? "nil" : "ok",
                request.insertAfterScroll ? "after-scroll" : "bottom-now"
            )
        )
        #endif

        // List の scrollTo は指定した時間・カーブを使わないため、
        // UIScrollView を CADisplayLink で自分で動かす（#282 レビュー）
        var handledByCustomScroll = false
        if let scrollView = listScrollView {
            // シートが閉じた直後はバーの余白がまだ確定していないことがある。
            // 止まった位置でもう一度確かめ、ずれていたら合わせ直す（最大2回）。
            for pass in 0..<2 {
                guard let target = spotlightScrollTarget(
                    for: first,
                    scrollView: scrollView,
                    startOffset: pass == 0
                        ? request.startOffset
                        : scrollView.contentOffset.y,
                    rowIsInserted: !request.insertAfterScroll
                ) else { break }
                handledByCustomScroll = true
                // 見えているなら送らない。送る場合も「見えるところまで」の最小距離だけ
                guard !target.isVisible, abs(target.to - target.from) >= 0.5 else {
                    break
                }
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
            if request.insertAfterScroll || request.revealInPlace {
                hiddenUntilDismissAlarmIDs.subtract(ids)
                pendingRevealAlarmIDs.formUnion(ids)
                syncDisplayedAlarms()
            }
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

        // スクロールが止まってから行を入れて開く
        if request.insertAfterScroll || request.revealInPlace {
            let mode = request.insertAfterScroll ? "after-scroll" : "bottom-reveal"
            if request.insertAfterScroll {
                insertRowsAfterScroll(ids)
            }
            #if DEBUG
            NSLog("%@", "[SpotlightReveal] insert mode=\(mode) ids=\(ids.count)")
            #endif
            // 中身の自然な高さが測れてから開く（測れる前に開くと全高で出る）
            await waitForRevealMeasurement(ids)
            guard !Task.isCancelled else { return }
            #if DEBUG
            let heights = ids
                .map { String(format: "%.1f", measuredRevealHeights[$0] ?? 0) }
                .joined(separator: ",")
            NSLog(
                "%@",
                "[SpotlightReveal] gap start mode=\(mode) heights=\(heights)"
            )
            #endif
            // 1) すき間だけを開ける（カードと中身は見えない）
            revealedAlarmIDs.formUnion(ids)
            if !reduceMotion {
                try? await Task.sleep(for: .seconds(RowSpotlightTiming.revealHeight))
                guard !Task.isCancelled else { return }
            }
            // 2) 開ききってから、カードと中身を一緒に出す
            #if DEBUG
            NSLog("%@", "[SpotlightReveal] show start mode=\(mode)")
            #endif
            withAnimation(RowSpotlightTiming.revealOpacityAnimation) {
                shownRevealAlarmIDs.formUnion(ids)
            }
        }

        // 入り終わってから約0.08秒後に光らせる
        try? await Task.sleep(for: .seconds(RowSpotlightTiming.glowDelayAfterReveal))
        guard !Task.isCancelled else { return }
        spotlightStore.play(ids)

        // 光るのと同じタイミングで、その行の2行目に次に鳴るまでの1文を出す（#289）
        if let untilRing = request.untilRing {
            untilRingNotice.show(untilRing.message, for: untilRing.alarmID)
        }

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
        shownRevealAlarmIDs.subtract(ids)
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

        let unlockWouldShow = !AppGroup.playlistUnlockShown
            && PlaylistUnlockLogic.trigger(
                hasPending: soundStore.hasPendingPlaylistUnlock,
                hasFiredAlarm: hasAlarmFired(),
                customSoundCount: soundStore.customSoundCount,
                playlistCount: PlaylistStore.shared.playlists.count,
                hasShown: AppGroup.playlistUnlockShown
            ) != nil
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
    /// 光っている行の2行目に出す1文（#289）
    let untilRingNotice: UntilRingNoticeController
    /// 全体の休みで止まっている行の終わり（#296）。nil なら止まっていない。
    let pausedUntil: Date?
    /// 上から何番目に止まっている行か（#296）。
    let pausedIndex: Int
    /// 帯が開ききるまで、層とアイコンを待たせる（#296 実機確認）。
    let pausedEntryDelay: TimeInterval
    /// 層をタップしたときに「しばらく鳴らさない」を開く（#296）。
    let onPausedTap: () -> Void
    let onFixSilentSound: () -> Void
    let onFirstAlarmFollowup: (FirstAlarmFollowupAction) -> Void
    let onToggle: () -> Void
    let onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .accessibilityLabel(Text(rowAccessibilityLabel))
            .accessibilityIdentifier("alarm.row")
            .accessibilityFocused(spotlightFocus, equals: alarm.id)

            // 初めての1回きりアラームのあとの提案（#247）。押すまで何も変えない。
            if showsFirstAlarmFollowup {
                followupButtons
            }
        }
        // 止まっている行は、カードと同じ形の層をかぶせる。行の高さは変えない（#296）。
        .overlay {
            PausedAlarmOverlay(
                isPaused: pausedUntil != nil,
                pausedIndex: pausedIndex,
                entryDelay: pausedEntryDelay,
                reduceMotion: reduceMotion,
                onTap: onPausedTap
            )
        }
    }

    /// 行の読み上げ。止まっている行は先頭に「鳴りません、6:00 まで。」を足す（#296）。
    private var rowAccessibilityLabel: String {
        var parts = [alarm.displayTime]
        if !alarm.label.isEmpty { parts.append(alarm.label) }
        if let skipSummaryText { parts.append(skipSummaryText) }
        if !alarm.repeatWeekdays.isEmpty { parts.append(repeatSummary) }
        parts.append(soundDisplayName)
        if let holidaySummary { parts.append(holidaySummary) }
        if hasSilentSound {
            parts.append(String(localized: "silent_alarm_warning"))
        }
        let rest = ListFormatter.localizedString(byJoining: parts)
        guard let pausedUntil else { return rest }
        let lead = String(
            format: String(localized: "skip_row_paused_a11y_fmt"),
            AlarmSkipFormat.dayAndTime(pausedUntil)
        )
        return "\(lead) \(rest)"
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
                if !alarm.label.isEmpty {
                    Text(alarm.label)
                        .font(.subheadline)
                        .foregroundStyle(labelColor)
                        .lineLimit(1)
                }
                metadataLineWithUntilRing(vertical: false)
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

            if !alarm.label.isEmpty {
                Text(alarm.label)
                    .font(.body)
                    .foregroundStyle(labelColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            metadataLineWithUntilRing(vertical: true)
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
        AlarmTimeText(
            hour: alarm.hour,
            minute: alarm.minute,
            typography: .alarmList(
                isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
            ),
            color: timeColor
        )
    }

    /// 1行目＝ラベル、2行目＝「曜日・音」（#174 PR-2）。
    /// 光っている行だけ、2行目を次に鳴るまでの1文にクロスフェードする（#289）。
    /// 行の高さを変えないよう、元の行は残したまま不透明度だけ下げ、上に重ねる。
    @ViewBuilder
    private func metadataLineWithUntilRing(vertical: Bool) -> some View {
        metadataLine(vertical: vertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(showsUntilRing ? 0 : 1)
            .overlay(alignment: .leading) {
                if showsUntilRing, let text = untilRingNotice.text {
                    untilRingLabel(text)
                        .transition(.opacity)
                }
            }
            .animation(untilRingAnimation, value: showsUntilRing)
    }

    private func untilRingLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "bell.fill")
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityIdentifier("alarm.row.untilRing")
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(Color.actionText)
        // 行の accessibilityLabel を変えない。UI テストのときだけ見えるようにする。
        .accessibilityHidden(!AppGroup.isUITestExposeUntilRing)
    }

    private var showsUntilRing: Bool {
        untilRingNotice.isVisible && untilRingNotice.alarmID == alarm.id
    }

    private var untilRingAnimation: Animation {
        if reduceMotion {
            // Reduce Motion はフェードのみ
            return .easeInOut(duration: UntilRingNoticeController.Timing.fade)
        }
        return showsUntilRing
            ? .timingCurve(0.05, 0.7, 0.1, 1, duration: 0.35)
            : .timingCurve(
                0.4, 0, 0.2, 1,
                duration: UntilRingNoticeController.Timing.exit
            )
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
            time: alarm.displayTime,
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
