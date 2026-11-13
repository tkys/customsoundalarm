import SwiftUI

/// アラームの「音」を1つ選ぶ画面（#160 PR-2）。
/// ライブラリと同じ並び（プレイリスト／自分の音／プリセット）から1つ選ぶ。
struct AlarmSoundChoiceView: View {
    @Binding var playlistID: UUID?
    @Binding var selectedSound: AlarmSound?

    @Environment(\.dismiss) private var dismiss
    @State private var store = PlaylistStore.shared
    @State private var soundStore = SoundStore.shared
    @State private var audioPlayer = AudioPlayer.shared
    @State private var editingPlaylist: Playlist?
    @State private var showingNewPlaylist = false

    private var importedCount: Int {
        SoundPickerLogic.mySounds(in: soundStore.sounds).count
    }

    var body: some View {
        List {
            SoundLibrarySections(
                isSelecting: true,
                selectedSound: $selectedSound,
                selectionActive: playlistID == nil,
                onSelect: { sound in
                    // 選んでも画面は閉じない。タップで鳴らした音を確かめてから戻れる（#196）
                    playlistID = nil
                    selectedSound = sound
                },
                middle: AnyView(playlistSectionView)
            )
        }
        .accessibilityIdentifier("alarmSoundChoice.root")
        .warmListBackground()
        .navigationTitle(String(localized: "sound"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            // 画面を閉じたら試し聴きを止める（#196）
            if SoundPreviewLogic.shouldStop(playingFileName: audioPlayer.playingFileName) {
                audioPlayer.stop()
            }
        }
        .onChange(of: selectedSound?.id) { _, newValue in
            // 取り込みで新しい音が選ばれたら、プレイリスト選択を解除する
            if newValue != nil { playlistID = nil }
        }
        .sheet(isPresented: $showingNewPlaylist) {
            NavigationStack {
                PlaylistEditorView(
                    playlist: nil,
                    creationSource: .soundChoice
                ) { playlist in
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

    // MARK: - Playlists (#207)

    @ViewBuilder
    private var playlistSectionView: some View {
        if store.playlists.isEmpty {
            if PlaylistSuggestionLogic.shouldShow(
                playlistCount: 0,
                importedSoundCount: importedCount
            ) {
                Section {
                    PlaylistSuggestionRow(
                        importedCount: importedCount,
                        subtitle: "playlist_suggestion_alarm_subtitle"
                    ) {
                        createSuggestedPlaylist()
                    }
                    .accessibilityIdentifier("alarmSoundChoice.playlistSuggestion")
                }
            }
        } else {
            Section {
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

                Button {
                    showingNewPlaylist = true
                } label: {
                    Label("playlist_new", systemImage: "plus")
                }
                .accessibilityIdentifier("alarmSoundChoice.addPlaylist")
            } header: {
                PlaylistSectionHeader()
            }
        }
    }

    private func createSuggestedPlaylist() {
        if let playlist = PlaylistSuggestionService.create() {
            playlistID = playlist.id
            selectedSound = nil
            dismiss()
        }
    }

    private func select(_ playlist: Playlist) {
        playlistID = playlist.id
        selectedSound = nil
        dismiss()
    }
}
