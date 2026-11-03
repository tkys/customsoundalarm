import SwiftUI

/// アラームの「音」を1つ選ぶ画面（#160 PR-1）。
/// プレイリストか1つの音を選ぶ。PR-2 でライブラリと同じ並びに置き換える。
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
                                playlistID = playlist.id
                                selectedSound = nil
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(playlist.name)
                                        Text(summary(for: playlist))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if playlistID == playlist.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
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
            } header: {
                Text("playlist_title")
            } footer: {
                Text("playlist_limit_note")
            }

            Section {
                NavigationLink {
                    SoundSelectionView(selectedSound: $selectedSound)
                        .onAppear { playlistID = nil }
                } label: {
                    HStack {
                        Label("sound_mode_single", systemImage: "music.note")
                        Spacer()
                        Text(selectedSound?.name ?? String(localized: "none"))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .accessibilityIdentifier("alarmSoundChoice.single")
            } header: {
                Text("sound")
            }
        }
        .accessibilityIdentifier("alarmSoundChoice.root")
        .navigationTitle(String(localized: "sound"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewPlaylist = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("alarmSoundChoice.addPlaylist")
            }
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

    private func summary(for playlist: Playlist) -> String {
        String(
            format: String(localized: "playlist_summary_fmt"),
            playOrderTitle(playlist.playOrder),
            playlist.trackCount
        )
    }

    private func playOrderTitle(_ order: PlaylistPlayOrder) -> String {
        switch order {
        case .inOrder: String(localized: "play_order_in_order")
        case .shuffle: String(localized: "play_order_shuffle")
        case .oneRandom: String(localized: "play_order_one_random")
        }
    }
}
