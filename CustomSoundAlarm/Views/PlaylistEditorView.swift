import SwiftUI

// MARK: - PlaylistEditorView

/// プレイリストの作成・編集（#151）。
struct PlaylistEditorView: View {
    let playlist: Playlist?
    let onSave: (Playlist) -> Void
    /// ライブラリから push するときは戻るボタンがあるのでキャンセルを出さない
    let showsCancel: Bool
    /// 新規作成時の計測用（#183）
    let creationSource: PlaylistSource

    @Environment(\.dismiss) private var dismiss
    @State private var store = PlaylistStore.shared
    @State private var name: String
    @State private var tracks: [PlaylistTrack]
    @State private var playOrder: PlaylistPlayOrder
    @State private var transition: PlaylistTransition
    @State private var showingTrackPicker = false
    @State private var audioPlayer = AudioPlayer.shared
    @State private var isRenderingPreview = false
    @State private var previewTask: Task<Void, Never>?

    init(
        playlist: Playlist?,
        showsCancel: Bool = true,
        creationSource: PlaylistSource = .library,
        onSave: @escaping (Playlist) -> Void
    ) {
        self.playlist = playlist
        self.showsCancel = showsCancel
        self.creationSource = creationSource
        self.onSave = onSave
        _name = State(
            initialValue: playlist?.name
                ?? String(localized: "playlist_new_default_name")
        )
        _tracks = State(initialValue: playlist?.tracks ?? [])
        _playOrder = State(initialValue: playlist?.playOrder ?? .inOrder)
        _transition = State(initialValue: playlist?.transition ?? .off)
    }

    private var totalSeconds: TimeInterval {
        Playlist(name: name, tracks: tracks)
            .totalSeconds(durations: store.durationsByFileName)
    }

    private var isOverLimit: Bool {
        totalSeconds > Playlist.maxTotalSeconds + 0.5
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !tracks.isEmpty
            && !isOverLimit
    }

    var body: some View {
        List {
            Section {
                TextField("playlist_name_placeholder", text: $name)
                    .accessibilityIdentifier("playlist.name")
            }

            Section {
                ForEach(tracks) { track in
                    HStack(spacing: 10) {
                        Image(systemName: "music.note")
                            .foregroundStyle(Color.textSecondary)
                        Text(store.trackDisplayName(for: track.soundFileName))
                        Spacer()
                        if let duration = store.durationsByFileName[track.soundFileName] {
                            Text(Self.durationText(duration))
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Button {
                            previewTrack(track)
                        } label: {
                            Image(systemName: isTrackPlaying(track)
                                ? "stop.circle.fill" : "play.circle")
                                .foregroundStyle(Color.actionText)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("preview"))
                        .accessibilityIdentifier(
                            "playlist.trackPlay.\(track.soundFileName)"
                        )
                    }
                }
                .onDelete { offsets in
                    let removed = offsets.map { tracks[$0] }
                    tracks.remove(atOffsets: offsets)
                    if removed.contains(where: isTrackPlaying) {
                        audioPlayer.stop()
                    }
                }
                .onMove { source, destination in
                    tracks.move(fromOffsets: source, toOffset: destination)
                }

                Button {
                    showingTrackPicker = true
                } label: {
                    Label("playlist_add_track", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("playlist.addTrack")
            } header: {
                WarmSectionHeader(title: String(localized: "playlist_tracks"))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(
                        format: String(localized: "playlist_total_fmt"),
                        Self.durationText(totalSeconds)
                    ))
                    if isOverLimit {
                        Text("playlist_limit_exceeded")
                            .foregroundStyle(.red)
                    } else {
                        Text("playlist_limit_note")
                    }
                }
                .foregroundStyle(Color.textSecondary)
            }

            Section {
                Button {
                    togglePlaylistPreview()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isPreviewPlaying
                            ? "stop.fill" : "play.circle")
                            .foregroundStyle(
                                isPreviewPlaying ? Color.red : Color.actionText
                            )
                        Text(isPreviewPlaying ? "stop" : "playlist_preview")
                        Spacer()
                        if isRenderingPreview {
                            ProgressView()
                        }
                    }
                }
                .disabled(tracks.isEmpty || isOverLimit || isRenderingPreview)
                .accessibilityIdentifier("playlist.preview")
            }

            Section {
                ForEach(PlaylistPlayOrder.allCases, id: \.self) { order in
                    Button {
                        playOrder = order
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(localizedPlayOrderTitle(order))
                                Text(playOrderWhenText(order))
                                    .font(.footnote)
                                    .foregroundStyle(Color.textSecondary)
                            }
                            Spacer()
                            if playOrder == order {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Brand.orange)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("playlist.playOrder.\(order.rawValue)")
                }

                Picker("transition", selection: $transition) {
                    Text("transition_off").tag(PlaylistTransition.off)
                    Text("transition_short").tag(PlaylistTransition.short)
                    Text("transition_long").tag(PlaylistTransition.long)
                    Text("transition_crossfade").tag(PlaylistTransition.crossfade)
                }
                .accessibilityIdentifier("playlist.transition")
            } header: {
                WarmSectionHeader(title: String(localized: "playlist_playback"))
            } footer: {
                Text("transition_footer")
            }

            Section {
                Text("playlist_early_access_note")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }

        }
        .warmListBackground()
        // 常にドラッグハンドルを出す（削除は標準の − ボタン・#169）。
        .environment(\.editMode, .constant(.active))
        .navigationTitle(
            playlist == nil
                ? String(localized: "playlist_new")
                : String(localized: "playlist_title")
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Text("cancel")
                    }
                    .tint(Color.primary)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button { save() } label: {
                    Text("save")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.actionFillEnd)
                .disabled(!canSave)
                .accessibilityIdentifier("playlist.save")
            }
        }
        .sheet(isPresented: $showingTrackPicker) {
            NavigationStack {
                PlaylistTrackPickerView(selected: $tracks)
            }
        }
        .onDisappear {
            previewTask?.cancel()
            isRenderingPreview = false
            audioPlayer.stop()
            PlaylistRenderService.shared.deletePreviewSound()
        }
    }

    // MARK: - Preview / reorder

    private var isPreviewPlaying: Bool {
        audioPlayer.isPlaying
            && audioPlayer.playingFileName == PlaylistRenderService.previewSoundFileName
    }

    private func isTrackPlaying(_ track: PlaylistTrack) -> Bool {
        audioPlayer.isPlaying && audioPlayer.playingFileName == track.soundFileName
    }

    private func previewTrack(_ track: PlaylistTrack) {
        previewTask?.cancel()
        isRenderingPreview = false
        if isPreviewPlaying {
            audioPlayer.stop()
        }
        PlaylistRenderService.shared.deletePreviewSound()

        guard let sound = SoundStore.shared.sounds.first(where: {
            $0.fileName == track.soundFileName
        }) else { return }

        if isTrackPlaying(track) {
            audioPlayer.stop()
        } else {
            audioPlayer.play(sound, source: .library)
        }
    }

    private func togglePlaylistPreview() {
        if isPreviewPlaying {
            audioPlayer.stop()
            PlaylistRenderService.shared.deletePreviewSound()
            return
        }
        guard !tracks.isEmpty, !isOverLimit, !isRenderingPreview else { return }

        audioPlayer.stop()
        isRenderingPreview = true
        previewTask?.cancel()
        let previewTracks = tracks
        let previewOrder = playOrder
        let previewTransition = transition
        previewTask = Task {
            let resolution = await PlaylistRenderService.shared.preparePreviewSound(
                tracks: previewTracks,
                playOrder: previewOrder,
                transition: previewTransition
            )
            guard !Task.isCancelled else {
                PlaylistRenderService.shared.deletePreviewSound()
                return
            }
            isRenderingPreview = false
            audioPlayer.playFile(fileName: resolution.fileName)
        }
    }

    private func playOrderWhenText(_ order: PlaylistPlayOrder) -> String {
        switch order {
        case .inOrder: String(localized: "play_order_when_in_order")
        case .shuffle: String(localized: "play_order_when_shuffle")
        case .oneRandom: String(localized: "play_order_when_one_random")
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !tracks.isEmpty, !isOverLimit else { return }
        let saved = Playlist(
            id: playlist?.id ?? UUID(),
            name: trimmed,
            tracks: tracks,
            playOrder: playOrder,
            transition: transition,
            createdAt: playlist?.createdAt ?? Date()
        )
        store.upsert(saved)

        if playlist == nil {
            AnalyticsService.shared.capture(.playlistCreated(
                trackCount: tracks.count,
                totalSecondsBucket: AnalyticsBuckets.playlistSecondsBucket(
                    seconds: totalSeconds
                ),
                playOrder: playOrder,
                transition: transition,
                source: creationSource
            ))
        } else {
            AnalyticsService.shared.capture(.playlistEdited(
                playOrder: playOrder,
                transition: transition
            ))
        }
        onSave(saved)
        dismiss()
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - PlaylistTrackPickerView

/// プレイリストに追加する曲を選ぶ（#151）。
struct PlaylistTrackPickerView: View {
    @Binding var selected: [PlaylistTrack]

    @Environment(\.dismiss) private var dismiss
    @State private var store = PlaylistStore.shared
    @State private var soundStore = SoundStore.shared
    @State private var showingLimitAlert = false

    private var totalSeconds: TimeInterval {
        Playlist(name: "", tracks: selected)
            .totalSeconds(durations: store.durationsByFileName)
    }

    /// ライブラリ・音の選択と同じ並び（最近使った順→新しい順）。
    private var importedSounds: [AlarmSound] {
        let existing = Set(soundStore.sounds.map(\.fileName))
        let recentNames = SoundUsageHistory.recentFileNames(
            limit: soundStore.sounds.count,
            existingFileNames: existing
        )
        return SoundPickerLogic.mySoundsByRecentUse(
            in: soundStore.sounds,
            recentFileNames: recentNames
        )
    }

    private var presets: [AlarmSound] {
        SoundPickerLogic.presetSounds(in: soundStore.sounds)
    }

    var body: some View {
        List {
            if !importedSounds.isEmpty {
                Section {
                    ForEach(importedSounds) { sound in
                        row(for: sound)
                    }
                } header: {
                    WarmSectionHeader(title: String(localized: "imported_sounds"))
                }
            }

            Section {
                ForEach(presets) { sound in
                    row(for: sound)
                }
            } header: {
                WarmSectionHeader(title: String(localized: "presets"))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(
                        format: String(localized: "playlist_total_fmt"),
                        PlaylistEditorView.durationText(totalSeconds)
                    ))
                    Text("playlist_limit_note")
                }
                .foregroundStyle(Color.textSecondary)
            }
        }
        .warmListBackground()
        .navigationTitle(String(localized: "playlist_select_track"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("close") { dismiss() }
                    .accessibilityIdentifier("playlist.closeTrackPicker")
            }
        }
    }

    /// 自分の音・同梱の音で共通の行。サムネイルと長さは既存の表示を使う。
    private func row(for sound: AlarmSound) -> some View {
        let isSelected = selected.contains {
            $0.soundFileName == sound.fileName
        }

        return Button {
            toggle(sound)
        } label: {
            HStack(spacing: 12) {
                SoundThumbnail(sound: sound, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(sound.name)
                        .fixedSize(horizontal: false, vertical: true)
                    if let duration = sound.durationSeconds {
                        Text(PlaylistEditorView.durationText(duration))
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Brand.orange)
                        .accessibilityIdentifier(
                            "playlist.trackSelected.\(sound.fileName)"
                        )
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("playlist.track.\(sound.fileName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func toggle(_ sound: AlarmSound) {
        if let index = selected.firstIndex(where: {
            $0.soundFileName == sound.fileName
        }) {
            selected.remove(at: index)
            return
        }
        let candidate = selected + [PlaylistTrack(soundFileName: sound.fileName)]
        let seconds = Playlist(name: "", tracks: candidate)
            .totalSeconds(durations: store.durationsByFileName)
        guard seconds <= Playlist.maxTotalSeconds + 0.5 else {
            showingLimitAlert = true
            return
        }
        selected = candidate
    }
}
