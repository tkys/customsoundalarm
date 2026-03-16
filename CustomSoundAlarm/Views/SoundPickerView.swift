import SwiftUI
import UniformTypeIdentifiers

/// サウンド選択画面
/// OOUI: アラームのプロパティとしてナビゲーション遷移で表示
/// 選択 + インポートを同一画面で完結させる
struct SoundSelectionView: View {
    @Binding var selectedSound: AlarmSound?
    @State private var soundStore = SoundStore.shared
    @State private var audioPlayer = AudioPlayer.shared
    @State private var isImporting = false
    @State private var isConverting = false
    @State private var errorMessage: String?
    @State private var renamingSound: AlarmSound?
    @State private var renameText = ""

    var body: some View {
        List {
            presetSection
            importedSection
            addSection
            errorSection
        }
        .warmListBackground()
        .navigationTitle(String(localized: "sound"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { audioPlayer.stop() }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: Self.supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
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

    // MARK: - Preset Sounds

    private var presetSection: some View {
        Section {
            soundRow(name: String(localized: "default_sound"), sound: nil, isPreset: true)

            ForEach(soundStore.sounds.filter(\.isPreset), id: \.id) { sound in
                soundRow(name: sound.name, sound: sound, isPreset: true)
            }
        } header: {
            WarmSectionHeader(title: String(localized: "presets"))
        }
    }

    // MARK: - Imported Sounds

    @ViewBuilder
    private var importedSection: some View {
        let imported = soundStore.sounds.filter { !$0.isPreset }
        Section {
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
                ForEach(imported, id: \.id) { sound in
                    soundRow(name: sound.name, sound: sound, isPreset: false)
                        .contextMenu {
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
                .onDelete { indexSet in
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

    // MARK: - Add Sound

    private var addSection: some View {
        Section {
            if isConverting {
                HStack {
                    ProgressView()
                    Text("converting")
                        .padding(.leading, 8)
                }
            } else {
                NavigationLink {
                    VideoImportFlow(selectedSound: $selectedSound)
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
            }
        } header: {
            WarmSectionHeader(title: String(localized: "add_section"))
        } footer: {
            Text("add_section_footer")
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

    // MARK: - Sound Row

    private func soundRow(name: String, sound: AlarmSound?, isPreset: Bool) -> some View {
        let isPlaying = sound != nil && audioPlayer.playingFileName == sound?.fileName

        return HStack {
            // Leading icon with glow when playing
            ZStack {
                if isPlaying {
                    Circle()
                        .fill(Color.accentColor.opacity(0.25))
                        .frame(width: 32, height: 32)
                        .blur(radius: 4)
                }

                Circle()
                    .fill(
                        isPlaying
                            ? Color.accentColor.opacity(0.18)
                            : (isPreset ? Brand.purpleLight.opacity(0.12) : Color.accentColor.opacity(0.12))
                    )
                    .frame(width: 28, height: 28)

                if isPlaying {
                    MiniWaveformBars(color: .accentColor, barWidth: 2, height: 12)
                } else {
                    SoundIndicator(isCustom: !isPreset, size: 13)
                }
            }
            .frame(width: 32)

            Button {
                selectedSound = sound
                audioPlayer.stop()
            } label: {
                HStack {
                    Text(name)
                    Spacer()
                    if selectedSound?.id == sound?.id {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                            .fontWeight(.semibold)
                    }
                }
                .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)

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

    // MARK: - Import

    private static let supportedTypes: [UTType] = [
        .mp3, .aiff, .wav, .mpeg4Audio,
        UTType("com.apple.coreaudio-format") ?? .audio,
        .audio
    ]

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importSound(from: url)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func importSound(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = String(localized: "file_access_denied")
            return
        }

        isConverting = true
        errorMessage = nil

        let name = url.deletingPathExtension().lastPathComponent

        Task {
            defer {
                url.stopAccessingSecurityScopedResource()
                isConverting = false
            }

            do {
                let fileName = try await AudioConverter.shared.convertToCAF(
                    from: url,
                    outputName: UUID().uuidString
                )

                let sound = AlarmSound(name: name, fileName: fileName)
                soundStore.add(sound)
                selectedSound = sound
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
