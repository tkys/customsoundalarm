import SwiftUI

/// ライブラリタブ（#160 PR-2）。
/// プレイリスト・自分の音・プリセットを、アラームから独立した「置き場所」としてまとめる。
struct LibraryView: View {
    @State private var store = PlaylistStore.shared
    @State private var alarmStore = AlarmStore.shared
    @State private var path: [UUID] = []
    @State private var showingNewPlaylist = false
    @State private var pendingDelete: Playlist?
    /// SoundLibrarySections が使う選択値（ライブラリでは試聴のみ）
    @State private var selectedSound: AlarmSound?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                playlistSection
                SoundLibrarySections(
                    isSelecting: false,
                    selectedSound: $selectedSound
                )
            }
            .accessibilityIdentifier("library.root")
            .warmListBackground()
            .navigationTitle(String(localized: "library_title"))
            .navigationDestination(for: UUID.self) { id in
                if let playlist = store.playlist(id: id) {
                    PlaylistEditorView(playlist: playlist, showsCancel: false) { _ in }
                } else {
                    Text("playlist_empty")
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showingNewPlaylist) {
                NavigationStack {
                    PlaylistEditorView(playlist: nil) { _ in }
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

    private var playlistSection: some View {
        Section {
            if store.playlists.isEmpty {
                Text("playlist_empty")
                    .foregroundStyle(.secondary)
            } else {
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
            }

            Button {
                showingNewPlaylist = true
            } label: {
                Label("playlist_new", systemImage: "plus")
            }
            .accessibilityIdentifier("library.addPlaylist")
        } header: {
            PlaylistSectionHeader()
        } footer: {
            Text("playlist_early_access_note")
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
