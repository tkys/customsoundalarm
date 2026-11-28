import SwiftUI

/// ライブラリタブ（#160 PR-2）。
/// プレイリスト・自分の音・プリセットを、アラームから独立した「置き場所」としてまとめる。
struct LibraryView: View {
    @State private var store = PlaylistStore.shared
    @State private var soundStore = SoundStore.shared
    @State private var alarmStore = AlarmStore.shared
    @State private var path: [UUID] = []
    @State private var showingNewPlaylist = false
    @State private var pendingDelete: Playlist?
    /// SoundLibrarySections が使う選択値（ライブラリでは試聴のみ）
    @State private var selectedSound: AlarmSound?
    /// プレイリストの解放（#216）
    @State private var unlock = PlaylistUnlockCoordinator.shared
    @State private var scheduler = AlarmScheduler.shared
    @State private var volumeBoostedFileName: String?
    @State private var shareLanding = ShareImportLanding.shared
    /// 共有から保存した行を一度だけ光らせる（#282 / #246）
    @State private var spotlight = RowSpotlightController()
    @State private var spotlightFileName: String?
    @State private var soundFrameStore = RowFrameStore<String>()
    @State private var listViewport: CGRect = .zero
    @State private var didRunLibraryLandingUITest = false
    @State private var musicLibrary = MusicLibraryImportController()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// サウンド一覧のバナー枠（#266）。試聴中は出さない。
    private var isPreviewingSound: Bool {
        AudioPlayer.shared.playingFileName != nil
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
            List {
                SoundLibrarySections(
                    isSelecting: false,
                    selectedSound: $selectedSound,
                    musicLibrary: musicLibrary,
                    middle: AnyView(playlistSection),
                    volumeBoostedFileName: $volumeBoostedFileName,
                    showVolumeNoticeRow: true,
                    onImportFlowDismissed: { schedulePlaylistUnlockAttempt() },
                    spotlight: spotlight,
                    spotlightFileName: spotlightFileName,
                    spotlightFrameStore: soundFrameStore,
                    onImportedSound: { handleLibraryImportSaved($0) }
                )

                #if DEBUG
                Section {
                    NavigationLink {
                        SyncLogView()
                    } label: {
                        Label("同期ログ", systemImage: "waveform.path.ecg")
                    }
                    .accessibilityIdentifier("library.syncLog")
                } header: {
                    WarmSectionHeader(title: String(localized: "開発者向け"))
                }
                #endif
            }
            .accessibilityIdentifier("library.root")
            .safeAreaInset(edge: .bottom) {
                // サウンド一覧の下部バナー枠（#266）。AdsConfig.isEnabled == false の間は
                // 高さ0・非表示で、判定と計測だけ行う。
                AdSlot(slot: .bannerSounds, isSuppressed: isPreviewingSound)
            }
            .task {
                #if DEBUG
                guard AppGroup.isUITestLibraryImportLanding,
                      !didRunLibraryLandingUITest,
                      let sound = soundStore.sounds.first(where: { !$0.isPreset })
                else { return }
                didRunLibraryLandingUITest = true
                try? await Task.sleep(for: .milliseconds(700))
                // UIテスト用: 小さい音を取り込んで音量を上げた状態を再現する（#224）
                if AppGroup.isUITestQuietCrop {
                    volumeBoostedFileName = sound.fileName
                }
                handleLibraryImportSaved(sound)
                #endif
            }
            .onChange(of: soundStore.hasPendingPlaylistUnlock) { _, hasPending in
                if hasPending { schedulePlaylistUnlockAttempt() }
            }
            .onChange(of: shareLanding.librarySoundFileName) { _, fileName in
                guard let fileName else { return }
                spotlightSharedSound(fileName, proxy: proxy)
            }
            .onChange(of: spotlight.isActive) { _, isActive in
                if !isActive { spotlightFileName = nil }
            }
            .onGeometryChange(for: CGRect.self) { geometry in
                let frame = geometry.frame(in: .global)
                let insets = geometry.safeAreaInsets
                return CGRect(
                    x: frame.minX + insets.leading,
                    y: frame.minY + insets.top,
                    width: max(0, frame.width - insets.leading - insets.trailing),
                    height: max(0, frame.height - insets.top - insets.bottom)
                )
            } action: { viewport in
                listViewport = viewport
            }
            .musicLibraryImport(musicLibrary)
            }
            .warmListBackground()
            .navigationTitle(String(localized: "library_title"))
            .navigationDestination(for: UUID.self) { id in
                if let playlist = store.playlist(id: id) {
                    PlaylistEditorView(playlist: playlist, showsCancel: false) { _ in }
                } else {
                    Text("playlist_empty")
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .sheet(isPresented: $showingNewPlaylist) {
                NavigationStack {
                    PlaylistEditorView(
                        playlist: nil,
                        creationSource: .library
                    ) { _ in }
                }
            }
            .confirmationDialog(
                "playlist_delete_title",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { playlist in
                Button("delete", role: .destructive) {
                    delete(playlist)
                }
                Button("cancel", role: .cancel) {
                    pendingDelete = nil
                }
            } message: { playlist in
                let count = PlaylistDeletionLogic.affectedAlarmCount(
                    playlistID: playlist.id,
                    alarms: alarmStore.alarms
                )
                if count > 0 {
                    Text(String(
                        format: String(localized: "playlist_delete_message_count_fmt"),
                        count
                    ))
                } else {
                    Text("playlist_delete_message_unused")
                }
            }
        }
    }

    // MARK: - Playlists

    private var importedCount: Int {
        SoundPickerLogic.mySounds(in: soundStore.sounds).count
    }

    @ViewBuilder
    private var playlistSection: some View {
        if store.playlists.isEmpty {
            if PlaylistSuggestionLogic.shouldShow(
                playlistCount: 0,
                importedSoundCount: importedCount
            ) {
                Section {
                    PlaylistSuggestionRow(
                        importedCount: importedCount,
                        subtitle: "playlist_suggestion_library_subtitle"
                    ) {
                        if let playlist = PlaylistSuggestionService.create() {
                            PlaylistApplyCoordinator.shared.offer(
                                playlist: playlist,
                                source: .suggestion
                            )
                        }
                    }
                    .accessibilityIdentifier("library.playlistSuggestion")
                }
            }
        } else {
            Section {
                ForEach(store.playlists) { playlist in
                    NavigationLink(value: playlist.id) {
                        PlaylistRowLabel(playlist: playlist)
                    }
                    .accessibilityIdentifier("library.playlist.\(playlist.name)")
                    .swipeActions {
                        Button(role: .destructive) {
                            pendingDelete = playlist
                        } label: {
                            Label("delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            pendingDelete = playlist
                        } label: {
                            Label("delete", systemImage: "trash")
                        }
                    }
                }

                Button {
                    showingNewPlaylist = true
                } label: {
                    Label("playlist_new", systemImage: "plus")
                }
                .accessibilityIdentifier("library.addPlaylist")
            } header: {
                PlaylistSectionHeader()
            }
        }
    }

    private func delete(_ playlist: Playlist) {
        PlaylistDeletionService.delete(playlistID: playlist.id)
        if path.last == playlist.id {
            path.removeLast()
        }
        pendingDelete = nil
    }

    /// ライブラリから取り込みを保存したあとの着地先（#246）。
    private func handleLibraryImportSaved(_ sound: AlarmSound) {
        let destination: ShareImportDestination
        if alarmStore.alarms.isEmpty {
            destination = .addAlarm
            shareLanding.addAlarmSound = sound
        } else {
            destination = .library
            shareLanding.librarySoundFileName = sound.fileName
        }
        AnalyticsService.shared.capture(.importLanded(
            source: .library,
            destination: destination
        ))
    }

    /// 共有から保存した音の行を見える位置に出して、一度だけ光らせる（#282 / #246）。
    private func spotlightSharedSound(_ fileName: String, proxy: ScrollViewProxy?) {
        let needsScroll = RowSpotlightLogic.shouldScroll(
            rowFrame: soundFrameStore.frame(for: fileName),
            viewport: listViewport
        )

        spotlightFileName = fileName
        var scrollDuration: TimeInterval = 0
        if needsScroll, let proxy {
            if reduceMotion {
                // 動きを減らす設定では位置だけ合わせる（#282）
                proxy.scrollTo("library.sound.\(fileName)", anchor: RowSpotlightTiming.scrollAnchor)
            } else {
                let distance = RowSpotlightLogic.scrollDistance(
                    rowFrame: soundFrameStore.frame(for: fileName),
                    viewport: listViewport
                )
                scrollDuration = RowSpotlightTiming.scrollDuration(for: distance)
                withAnimation(RowSpotlightTiming.scrollAnimation(duration: scrollDuration)) {
                    proxy.scrollTo(
                        "library.sound.\(fileName)",
                        anchor: RowSpotlightTiming.scrollAnchor
                    )
                }
            }
        }

        // 行はすでにあるので、止まってから光らせる（#282 / #246）
        let startDelay = scrollDuration > 0
            ? scrollDuration + RowSpotlightTiming.glowDelayAfterReveal
            : 0
        spotlight.play(startDelay: startDelay)
        shareLanding.librarySoundFileName = nil
    }

    /// 取り込み画面が閉じてから解放シートを出す（#216）。
    private func schedulePlaylistUnlockAttempt() {
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            attemptPlaylistUnlock()
        }
    }

    private func attemptPlaylistUnlock() {
        guard !showingNewPlaylist,
              pendingDelete == nil,
              path.isEmpty else { return }
        _ = unlock.presentIfNeeded(
            isRinging: scheduler.isAlarmRinging,
            isNightMode: BedsideModeTracker.shared.isActive
        )
    }
}
