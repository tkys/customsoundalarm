import SwiftUI

/// ライブラリとアラームの音選択で共通の「自分の音」「プリセット」（#160 PR-2）。
///
/// `List` の直下に置くと、そのまま2つの Section として表示される。
struct SoundLibrarySections: View {
    /// true = アラームの音を選ぶ / false = ライブラリで管理する
    let isSelecting: Bool
    @Binding var selectedSound: AlarmSound?
    /// 選択モードで1つ選ばれたとき（プレイリスト選択中はチェックを出さない）
    var selectionActive: Bool = true
    var onSelect: ((AlarmSound?) -> Void)?

    @State private var soundStore = SoundStore.shared
    @State private var audioPlayer = AudioPlayer.shared
    @State private var isImporting = false
    @State private var pendingAudio: PendingAudioImport?
    @State private var showingVideoImport = false
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
        Group {
            importedSection
            presetSection
            errorSection
        }
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
    }

    // MARK: - My Sounds

    @ViewBuilder
    private var importedSection: some View {
        let imported = importedSounds
        Section {
            Button {
                showingVideoImport = true
            } label: {
                Label {
                    Text("add_from_video")
                } icon: {
                    Image(systemName: "video.badge.waveform")
                        .foregroundStyle(Brand.purpleLight)
                        .padding(4)
                        .background(
                            Circle()
                                .fill(Brand.purpleLight.opacity(0.12))
                        )
                }
            }
            .accessibilityIdentifier("soundPicker.addVideo")

            Button {
                isImporting = true
            } label: {
                Label {
                    Text("add_from_audio")
                } icon: {
                    Image(systemName: "doc.badge.plus")
                        .foregroundStyle(Color.accentColor)
                        .padding(4)
                        .background(
                            Circle()
                                .fill(Color.accentColor.opacity(0.12))
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ForEach(Array(imported.enumerated()), id: \.element.id) { index, sound in
                    soundRow(
                        name: sound.name,
                        sound: sound,
                        isPreset: false,
                        position: index + 1
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

    // MARK: - Presets

    @ViewBuilder
    private var presetSection: some View {
        let presets = presets
        Section {
            if isSelecting {
                soundRow(
                    name: String(localized: "default_sound"),
                    sound: nil,
                    isPreset: true,
                    position: 1
                )
            }
            ForEach(Array(presets.enumerated()), id: \.element.id) { index, sound in
                soundRow(
                    name: sound.name,
                    sound: sound,
                    isPreset: true,
                    position: index + (isSelecting ? 2 : 1)
                )
            }
        } header: {
            WarmSectionHeader(title: String(localized: "presets"))
        }
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

    // MARK: - Row

    private func soundRow(
        name: String,
        sound: AlarmSound?,
        isPreset: Bool,
        position: Int
    ) -> some View {
        let isPlaying = sound != nil && audioPlayer.playingFileName == sound?.fileName
        let isSelected = isSelecting
            && selectionActive
            && selectedSound?.id == sound?.id
            && (sound != nil || selectedSound == nil)

        return HStack {
            ZStack {
                if isPlaying {
                    Circle()
                        .fill(Color.accentColor.opacity(0.25))
                        .frame(width: 38, height: 38)
                        .blur(radius: 4)
                }

                SoundThumbnail(sound: sound, size: 34)

                if isPlaying {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                        .frame(width: 34, height: 34)
                }
            }
            .frame(width: 38)

            Button {
                if isSelecting {
                    selectedSound = sound
                    let kind: SoundSelectionKind = sound == nil
                        ? .default
                        : (isPreset ? .preset : .imported)
                    AnalyticsService.shared.capture(.soundSelected(
                        kind: kind,
                        rankBucket: SoundSelectionAnalytics.rankBucket(position: position)
                    ))
                    onSelect?(sound)
                } else if let sound {
                    togglePreview(sound)
                }
            } label: {
                HStack {
                    Text(name)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                            .fontWeight(.semibold)
                    }
                }
                .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)
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
                        audioPlayer.play(sound)
                    }
                } label: {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle")
                        .font(.title3)
                        .foregroundStyle(
                            isPlaying
                                ? AnyShapeStyle(Brand.warmGoldGradient)
                                : AnyShapeStyle(Color.accentColor)
                        )
                        .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func togglePreview(_ sound: AlarmSound) {
        if audioPlayer.playingFileName == sound.fileName {
            audioPlayer.stop()
        } else {
            audioPlayer.play(sound)
        }
    }
}
