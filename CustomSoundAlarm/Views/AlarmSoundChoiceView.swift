import SwiftUI

/// アラームの「音」を1つ選ぶ画面（#160 PR-2）。
/// ライブラリと同じ並び（プレイリスト／自分の音／プリセット）から1つ選ぶ。
struct AlarmSoundChoiceView: View {
    @Binding var playlistID: UUID?
    @Binding var selectedSound: AlarmSound?

    @Environment(\.dismiss) private var dismiss
    @State private var store = PlaylistStore.shared
    @State private var editingPlaylist: Playlist?
    @State private var showingNewPlaylist = false

    var body: some View {
        List {
            Section {
                if store.playlists.isEmpty {
                    Text("playlist_empty")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.playlists) { playlist in
                        HStack(spacing: 12) {
                            Button {
                                select(playlist)
                            } label: {
                                PlaylistRowLabel(
                                    playlist: playlist,
                                    isSelected: playlistID == playlist.id
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(
                                "alarmSoundChoice.playlist.\(playlist.name)"
                            )

                            Button {
                                editingPlaylist = playlist
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text("edit"))
                            .accessibilityIdentifier(
                                "alarmSoundChoice.edit.\(playlist.name)"
                            )
                        }
                    }
                }

                Button {
                    showingNewPlaylist = true
                } label: {
                    Label("playlist_new", systemImage: "plus")
                }
                .accessibilityIdentifier("alarmSoundChoice.addPlaylist")
            } header: {
                PlaylistSectionHeader()
            }

            SoundLibrarySections(
                isSelecting: true,
                selectedSound: $selectedSound,
                selectionActive: playlistID == nil,
                onSelect: { sound in
                    playlistID = nil
                    selectedSound = sound
                    dismiss()
                }
            )
        }
        .accessibilityIdentifier("alarmSoundChoice.root")
        .navigationTitle(String(localized: "sound"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedSound?.id) { _, newValue in
            // 取り込みで新しい音が選ばれたら、プレイリスト選択を解除する
            if newValue != nil { playlistID = nil }
        }
        .sheet(isPresented: $showingNewPlaylist) {
            NavigationStack {
                PlaylistEditorView(playlist: nil) { playlist in
                    playlistID = playlist.id
                    selectedSound = nil
                }
            }
        }
        .sheet(item: $editingPlaylist) { playlist in
            NavigationStack {
                PlaylistEditorView(playlist: playlist) { _ in }
            }
        }
    }

    private func select(_ playlist: Playlist) {
        playlistID = playlist.id
        selectedSound = nil
        dismiss()
    }
}
