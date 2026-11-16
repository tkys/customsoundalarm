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

    var body: some View {
        NavigationStack(path: $path) {
            List {
                SoundLibrarySections(
                    isSelecting: false,
                    selectedSound: $selectedSound,
                    middle: AnyView(playlistSection)
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
                        _ = PlaylistSuggestionService.create()
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
}
