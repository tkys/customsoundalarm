import SwiftUI

// MARK: - PlaylistEditorView

/// プレイリストの作成・編集（#151）。
struct PlaylistEditorView: View {
    let playlist: Playlist?
    let onSave: (Playlist) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var store = PlaylistStore.shared
    @State private var name: String
    @State private var tracks: [PlaylistTrack]
    @State private var playOrder: PlaylistPlayOrder
    @State private var transition: PlaylistTransition
    @State private var showingTrackPicker = false

    init(playlist: Playlist?, onSave: @escaping (Playlist) -> Void) {
        self.playlist = playlist
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
                    HStack {
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                        Text(store.trackDisplayName(for: track.soundFileName))
                        Spacer()
                        if let duration = store.durationsByFileName[track.soundFileName] {
                            Text(Self.durationText(duration))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    tracks.remove(atOffsets: offsets)
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
                Text("playlist_tracks")
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
            }

            Section {
                Picker("play_order", selection: $playOrder) {
                    Text("play_order_in_order").tag(PlaylistPlayOrder.inOrder)
                    Text("play_order_shuffle").tag(PlaylistPlayOrder.shuffle)
                    Text("play_order_one_random").tag(PlaylistPlayOrder.oneRandom)
                }
                .accessibilityIdentifier("playlist.playOrder")

                Picker("transition", selection: $transition) {
                    Text("transition_off").tag(PlaylistTransition.off)
                    Text("transition_short").tag(PlaylistTransition.short)
                    Text("transition_long").tag(PlaylistTransition.long)
                    Text("transition_crossfade").tag(PlaylistTransition.crossfade)
                }
                .accessibilityIdentifier("playlist.transition")
            } header: {
                Text("playlist_playback")
            } footer: {
                Text("transition_footer")
            }

        }
        .navigationTitle(
            playlist == nil
                ? String(localized: "playlist_new")
                : String(localized: "playlist_title")
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("save") { save() }
                    .disabled(!canSave)
                    .accessibilityIdentifier("playlist.save")
            }
        }
        .sheet(isPresented: $showingTrackPicker) {
            NavigationStack {
                PlaylistTrackPickerView(selected: $tracks)
            }
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
                transition: transition
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

// MARK: - PlaylistPickerView

/// プレイリストの選択・管理（#151）。
struct PlaylistPickerView: View {
    @Binding var selectedPlaylistID: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var store = PlaylistStore.shared
    @State private var editingPlaylist: Playlist?
    @State private var showingNewPlaylist = false

    var body: some View {
        List {
            if store.playlists.isEmpty {
                Section {
                    Text("playlist_empty")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(store.playlists) { playlist in
                        HStack(spacing: 12) {
                            Button {
                                selectedPlaylistID = playlist.id
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(playlist.name)
                                        Text(String(
                                            format: String(localized: "playlist_track_count_fmt"),
                                            playlist.trackCount
                                        ))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedPlaylistID == playlist.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("playlist.select.\(playlist.name)")

                            Button {
                                editingPlaylist = playlist
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text("edit"))
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                PlaylistDeletionService.delete(playlistID: playlist.id)
                                if selectedPlaylistID == playlist.id {
                                    selectedPlaylistID = nil
                                }
                            } label: {
                                Label("delete", systemImage: "trash")
                            }
                        }
                    }
                } footer: {
                    Text("playlist_limit_note")
                }
            }
        }
        .navigationTitle(String(localized: "playlist_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewPlaylist = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("playlist.add")
            }
        }
        .sheet(isPresented: $showingNewPlaylist) {
            NavigationStack {
                PlaylistEditorView(playlist: nil) { playlist in
                    selectedPlaylistID = playlist.id
                }
            }
        }
        .sheet(item: $editingPlaylist) { playlist in
            NavigationStack {
                PlaylistEditorView(playlist: playlist) { _ in }
            }
        }
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

    var body: some View {
        List {
            Section {
                ForEach(soundStore.sounds) { sound in
                    Button {
                        toggle(sound)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sound.name)
                                if let duration = sound.durationSeconds {
                                    Text(PlaylistEditorView.durationText(duration))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if selected.contains(where: {
                                $0.soundFileName == sound.fileName
                            }) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("playlist.track.\(sound.fileName)")
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(
                        format: String(localized: "playlist_total_fmt"),
                        PlaylistEditorView.durationText(totalSeconds)
                    ))
                    Text("playlist_limit_note")
                }
            }
        }
        .navigationTitle(String(localized: "playlist_select_track"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("close") { dismiss() }
                    .accessibilityIdentifier("playlist.closeTrackPicker")
            }
        }
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
