import SwiftUI

/// ライブラリとアラームの音選択で共通の「自分の音」「標準の音」（#160 PR-2 / #207）。
///
/// `List` の直下に置くと、そのまま Section として表示される。
/// `middle` にはプレイリストの Section を挟める（#207）。
struct SoundLibrarySections: View {
    /// true = アラームの音を選ぶ / false = ライブラリで管理する
    let isSelecting: Bool
    @Binding var selectedSound: AlarmSound?
    /// 選択モードで1つ選ばれたとき（プレイリスト選択中はチェックを出さない）
    var selectionActive: Bool = true
    var onSelect: ((AlarmSound?) -> Void)?
    /// 取り込んだ音と標準の音の間に置く Section（プレイリスト・#207）
    var middle: AnyView?

    @State private var soundStore = SoundStore.shared
    @State private var audioPlayer = AudioPlayer.shared
    @State private var isImporting = false
    @State private var pendingAudio: PendingAudioImport?
    @State private var showingVideoImport = false
    @State private var showingStandardSounds = false
    @State private var errorMessage: String?
    @State private var renamingSound: AlarmSound?
    @State private var renameText = ""

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
        // 取り込み・名前変更の提示は「動画から音声を追加」の行1つだけに付ける（下の addVideo）。
        // Group や Section に付けると、List の中では各セクション・各行に複製され、
        // 同じシートを何度も開こうとして失敗し、アラームの追加画面ごと閉じてしまう（1.8.1・実機で再現）。
        importedSection
        if let middle { middle }
        standardSection
        errorSection
    }

    // MARK: - My Sounds

    @ViewBuilder
    private var importedSection: some View {
        let imported = importedSounds
        Section {
            Button {
                if SoundPreviewLogic.shouldStop(playingFileName: audioPlayer.playingFileName) {
                    audioPlayer.stop()
                }
                showingVideoImport = true
            } label: {
                Label {
                    Text("add_from_video")
                } icon: {
                    Image(systemName: "video.badge.waveform")
                        .foregroundStyle(Color.actionText)
                        .padding(4)
                        .background(
                            Circle()
                                .fill(Color.actionText.opacity(0.12))
                        )
                }
            }
            .accessibilityIdentifier("soundPicker.addVideo")
            .soundImport(
                selectedSound: $selectedSound,
                isImporting: $isImporting,
                pendingAudio: $pendingAudio,
                showingVideoImport: $showingVideoImport,
                errorMessage: $errorMessage
            )
            .alert(String(localized: "rename"), isPresented: Binding(
                get: { renamingSound != nil },
                set: { if !$0 { renamingSound = nil } }
            )) {
                TextField("sound_name_placeholder", text: $renameText)
                Button("save") {
                    if let sound = renamingSound, !renameText.isEmpty {
                        soundStore.rename(sound, to: renameText)
                        if selectedSound?.id == sound.id {
                            selectedSound = soundStore.sounds.first { $0.id == sound.id }
                        }
                    }
                    renamingSound = nil
                }
                Button("cancel", role: .cancel) { renamingSound = nil }
            }

            Button {
                if SoundPreviewLogic.shouldStop(playingFileName: audioPlayer.playingFileName) {
                    audioPlayer.stop()
                }
                isImporting = true
            } label: {
                Label {
                    Text("add_from_audio")
                } icon: {
                    Image(systemName: "doc.badge.plus")
                        .foregroundStyle(Color.actionText)
                        .padding(4)
                        .background(
                            Circle()
                                .fill(Color.actionText.opacity(0.12))
                        )
                }
            }
            .accessibilityIdentifier("soundPicker.addAudio")

            if imported.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.badge.plus")
                        .font(.title2)
                        .foregroundStyle(Brand.purpleLight)
                    Text("my_sounds_empty_title")
                        .font(.subheadline.weight(.medium))
                    Text("my_sounds_empty_description")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ForEach(Array(imported.enumerated()), id: \.element.id) { index, sound in
                    SoundSelectionRow(
                        name: sound.name,
                        sound: sound,
                        isPreset: false,
                        position: index + 1,
                        isSelecting: isSelecting,
                        selectionActive: selectionActive,
                        selectedSound: $selectedSound,
                        onSelect: onSelect
                    )
                    .contextMenu {
                        if !isSelecting {
                            Button {
                                renameText = sound.name
                                renamingSound = sound
                            } label: {
                                Label("rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                soundStore.remove(sound)
                            } label: {
                                Label("delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .onDelete { indexSet in
                    guard !isSelecting else { return }
                    let targets = imported
                    for index in indexSet {
                        soundStore.remove(targets[index])
                    }
                }
            }
        } header: {
            WarmSectionHeader(title: String(localized: "imported_sounds"))
        }
    }

    // MARK: - Standard sounds (#207)

    @ViewBuilder
    private var standardSection: some View {
        Section {
            Button {
                showingStandardSounds = true
            } label: {
                HStack(spacing: 12) {
                    Label {
                        Text(String(
                            format: String(localized: "standard_sounds_fmt"),
                            1 + presets.count
                        ))
                    } icon: {
                        Image(systemName: "music.note")
                            .foregroundStyle(Color.actionText)
                            .padding(4)
                            .background(
                                Circle()
                                    .fill(Color.actionText.opacity(0.12))
                            )
                    }
                    Spacer(minLength: 8)
                    if let selectedStandardName {
                        Text(selectedStandardName)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .accessibilityIdentifier("library.standardSounds")
            .sheet(isPresented: $showingStandardSounds) {
                StandardSoundsSheet(
                    presets: presets,
                    isSelecting: isSelecting,
                    selectionActive: selectionActive,
                    selectedSound: $selectedSound,
                    onSelect: onSelect
                )
            }
        }
    }

    /// 選んでいる音が標準の音なら、その名前。ライブラリでは出さない。
    private var selectedStandardName: String? {
        guard isSelecting, selectionActive else { return nil }
        if let sound = selectedSound {
            return sound.isPreset ? sound.name : nil
        }
        return String(localized: "default_sound")
    }

    // MARK: - Error

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage {
            Section {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }
}

// MARK: - Standard sounds sheet

/// 既定の音＋プリセットの一覧（#207）。
struct StandardSoundsSheet: View {
    let presets: [AlarmSound]
    let isSelecting: Bool
    let selectionActive: Bool
    @Binding var selectedSound: AlarmSound?
    var onSelect: ((AlarmSound?) -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SoundSelectionRow(
                        name: String(localized: "default_sound"),
                        sound: nil,
                        isPreset: true,
                        position: 1,
                        isSelecting: isSelecting,
                        selectionActive: selectionActive,
                        selectedSound: $selectedSound,
                        onSelect: onSelect
                    )
                    ForEach(Array(presets.enumerated()), id: \.element.id) { index, sound in
                        SoundSelectionRow(
                            name: sound.name,
                            sound: sound,
                            isPreset: true,
                            position: index + 2,
                            isSelecting: isSelecting,
                            selectionActive: selectionActive,
                            selectedSound: $selectedSound,
                            onSelect: onSelect
                        )
                    }
                }
            }
            .warmListBackground()
            .navigationTitle(String(localized: "standard_sounds_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Row

/// サウンド1行。選ぶ画面では選ぶと同時に鳴らし、再生ボタンは選ばずに鳴らす（#196）。
struct SoundSelectionRow: View {
    let name: String
    let sound: AlarmSound?
    let isPreset: Bool
    let position: Int
    let isSelecting: Bool
    let selectionActive: Bool
    @Binding var selectedSound: AlarmSound?
    var onSelect: ((AlarmSound?) -> Void)?

    @State private var audioPlayer = AudioPlayer.shared

    private var isPlaying: Bool {
        sound != nil && audioPlayer.playingFileName == sound?.fileName
    }

    private var isSelected: Bool {
        isSelecting
            && selectionActive
            && selectedSound?.id == sound?.id
            && (sound != nil || selectedSound == nil)
    }

    var body: some View {
        HStack {
            ZStack {
                if isPlaying {
                    Circle()
                        .fill(Brand.orange.opacity(0.25))
                        .frame(width: 38, height: 38)
                        .blur(radius: 4)
                }

                SoundThumbnail(sound: sound, size: 34)

                if isPlaying {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Brand.orange, lineWidth: 1.5)
                        .frame(width: 34, height: 34)
                }
            }
            .frame(width: 38)

            Button {
                if isSelecting {
                    handleSelectionTap()
                } else if let sound {
                    togglePreview(sound)
                }
            } label: {
                HStack {
                    Text(name)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Brand.orange)
                            .fontWeight(.semibold)
                    }
                }
                .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier(
                isPreset
                    ? "library.preset.\(sound?.fileName ?? "default")"
                    : "library.sound.\(sound?.fileName ?? "")"
            )

            if let sound {
                Button {
                    if audioPlayer.playingFileName == sound.fileName {
                        audioPlayer.stop()
                    } else {
                        audioPlayer.play(sound, source: .playButton)
                    }
                } label: {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle")
                        .font(.title3)
                        .foregroundStyle(Color.actionText)
                        .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? Text("stop") : Text("preview"))
                .accessibilityIdentifier("soundPicker.preview.\(sound.fileName)")
            }
        }
    }

    private func handleSelectionTap() {
        let outcome = SoundPreviewLogic.tap(
            tapped: sound,
            selected: selectedSound,
            playingFileName: audioPlayer.playingFileName,
            isActiveSelection: isSelected
        )

        if outcome.stops {
            audioPlayer.stop()
        }
        if outcome.notifiesSelection {
            selectedSound = sound
            onSelect?(sound)
        }
        if outcome.selectionChanged {
            let kind: SoundSelectionKind = sound == nil
                ? .default
                : (isPreset ? .preset : .imported)
            AnalyticsService.shared.capture(.soundSelected(
                kind: kind,
                rankBucket: SoundSelectionAnalytics.rankBucket(position: position)
            ))
        }
        if outcome.plays, let sound {
            audioPlayer.play(sound, source: .selectTap)
        }
    }

    private func togglePreview(_ sound: AlarmSound) {
        if audioPlayer.playingFileName == sound.fileName {
            audioPlayer.stop()
        } else {
            audioPlayer.play(sound, source: .library)
        }
    }
}
