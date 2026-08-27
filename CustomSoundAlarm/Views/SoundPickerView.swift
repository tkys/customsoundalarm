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
    @State private var errorMessage: String?
    @State private var renamingSound: AlarmSound?
    @State private var renameText = ""

    /// 波形クロップ待ちの音声取り込み（#77）。非nilでシートを表示
    @State private var pendingAudio: PendingAudioImport?

    // プリセット開閉状態
    @State private var presetExpanded: Bool = SoundPickerLogic.presetExpandedDefault(
        importedCount: SoundStore.shared.sounds.filter { !$0.isPreset }.count,
        userOverride: AppGroup.presetExpandedOverride
    )

    var body: some View {
        List {
            addSection
            importedSection
            recentSection
            presetSection
            errorSection
        }
        .warmListBackground()
        .navigationTitle(String(localized: "sound"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink {
                        VideoImportFlow(selectedSound: $selectedSound)
                    } label: {
                        Label("add_from_video", systemImage: "video.badge.waveform")
                    }
                    Button {
                        isImporting = true
                    } label: {
                        Label("add_from_audio", systemImage: "doc.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
            }
        }
        .onDisappear { audioPlayer.stop() }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: Self.supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        // 音声ファイルの波形クロップ（#77）
        .sheet(item: $pendingAudio) { pending in
            NavigationStack {
                AudioCropView(source: pending, selectedSound: $selectedSound)
            }
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

    // MARK: - Add Sound (最上位)

    private var addSection: some View {
        Section {
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
        } header: {
            WarmSectionHeader(title: String(localized: "add_section"))
        } footer: {
            Text("add_section_footer")
        }
    }

    // MARK: - Imported Sounds (主役)

    @ViewBuilder
    private var importedSection: some View {
        let excluded = recentFileNamesSet
        let imported = soundStore.sounds.filter { !$0.isPreset && !excluded.contains($0.fileName) }
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

    // MARK: - Recent Sounds

    /// 現存する音のうち最近使ったもの（新しい順、最大5件）。
    private var recentSounds: [AlarmSound] {
        let existing = Set(soundStore.sounds.map(\.fileName))
        return SoundUsageHistory.recentFileNames(limit: 5, existingFileNames: existing)
            .compactMap { name in soundStore.sounds.first { $0.fileName == name } }
    }

    private var recentFileNamesSet: Set<String> {
        Set(recentSounds.map(\.fileName))
    }

    private var importedCount: Int {
        soundStore.sounds.filter { !$0.isPreset }.count
    }

    @ViewBuilder
    private var recentSection: some View {
        let recents = recentSounds
        let shouldShow = SoundPickerLogic.shouldShowRecent(
            recentCount: recents.count,
            importedCount: importedCount
        )
        if shouldShow {
            Section {
                ForEach(recents, id: \.id) { sound in
                    soundRow(name: sound.name, sound: sound, isPreset: sound.isPreset, fromRecent: true)
                        .contextMenu {
                            if !sound.isPreset {
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
            } header: {
                WarmSectionHeader(title: String(localized: "recent_sounds"))
            }
        }
    }

    // MARK: - Preset Sounds (折りたたみ)

    @ViewBuilder
    private var presetSection: some View {
        let excluded = recentFileNamesSet
        let presets = soundStore.sounds.filter { $0.isPreset && !excluded.contains($0.fileName) }
        Section {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { presetExpanded },
                    set: { newVal in
                        presetExpanded = newVal
                        AppGroup.presetExpandedOverride = newVal
                    }
                )
            ) {
                soundRow(name: String(localized: "default_sound"), sound: nil, isPreset: true)
                ForEach(presets, id: \.id) { sound in
                    soundRow(name: sound.name, sound: sound, isPreset: true)
                }
            } label: {
                HStack {
                    Text(String(localized: "presets"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.purpleLight)
                    Text("(\(presets.count + 1))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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

    private func soundRow(name: String, sound: AlarmSound?, isPreset: Bool, fromRecent: Bool = false) -> some View {
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

            // 行全体をタップで選択（試聴は別ボタン）
            // 判断: タップで試聴を併用しない（誤タップで音が鳴るのを避ける）
            Button {
                selectedSound = sound
                audioPlayer.stop()
                if fromRecent {
                    AnalyticsService.shared.capture(.soundPickerRecentUsed)
                }
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

    /// 選択された音声ファイルを波形クロップUIに渡す（#77）。
    /// security-scoped resource の寿命を最小化するため、
    /// 選択直後に temp へコピー → 即解放する（VideoImportFlow の罠1 対策と同じ）。
    /// 変換・保存はクロップUI（AudioCropView）内で行う。
    private func importSound(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = String(localized: "file_access_denied")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).\(url.pathExtension)")
        do {
            try FileManager.default.copyItem(at: url, to: tempURL)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        pendingAudio = PendingAudioImport(
            url: tempURL,
            name: url.deletingPathExtension().lastPathComponent
        )
    }
}
