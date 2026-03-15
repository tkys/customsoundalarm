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
        .navigationTitle("サウンド")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { audioPlayer.stop() }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: Self.supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("名前を変更", isPresented: Binding(
            get: { renamingSound != nil },
            set: { if !$0 { renamingSound = nil } }
        )) {
            TextField("サウンド名", text: $renameText)
            Button("保存") {
                if let sound = renamingSound, !renameText.isEmpty {
                    soundStore.rename(sound, to: renameText)
                    if selectedSound?.id == sound.id {
                        selectedSound = soundStore.sounds.first { $0.id == sound.id }
                    }
                }
                renamingSound = nil
            }
            Button("キャンセル", role: .cancel) { renamingSound = nil }
        }
    }

    // MARK: - Preset Sounds

    private var presetSection: some View {
        Section("プリセット") {
            // 「なし」選択肢（デフォルト音）
            soundRow(name: "デフォルト", sound: nil)

            ForEach(soundStore.sounds.filter(\.isPreset), id: \.id) { sound in
                soundRow(name: sound.name, sound: sound)
            }
        }
    }

    // MARK: - Imported Sounds

    @ViewBuilder
    private var importedSection: some View {
        let imported = soundStore.sounds.filter { !$0.isPreset }
        if !imported.isEmpty {
            Section("追加した音") {
                ForEach(imported, id: \.id) { sound in
                    soundRow(name: sound.name, sound: sound)
                        .contextMenu {
                            Button {
                                renameText = sound.name
                                renamingSound = sound
                            } label: {
                                Label("名前を変更", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                soundStore.remove(sound)
                            } label: {
                                Label("削除", systemImage: "trash")
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
        }
    }

    // MARK: - Add Sound

    private var addSection: some View {
        Section {
            if isConverting {
                HStack {
                    ProgressView()
                    Text("変換中...")
                        .padding(.leading, 8)
                }
            } else {
                NavigationLink {
                    VideoImportFlow(selectedSound: $selectedSound)
                } label: {
                    Label("動画から音声を追加", systemImage: "video.badge.waveform")
                }

                Button {
                    isImporting = true
                } label: {
                    Label("音声ファイルから追加", systemImage: "doc.badge.plus")
                }
            }
        } header: {
            Text("追加")
        } footer: {
            Text("動画: カメラロールから選択してトリム\n音声ファイル: MP3, AAC, WAV, M4A 形式に対応")
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

    private func soundRow(name: String, sound: AlarmSound?) -> some View {
        HStack {
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
                    Image(systemName: audioPlayer.playingFileName == sound.fileName
                        ? "stop.circle.fill" : "play.circle")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.variableColor.iterative,
                                      isActive: audioPlayer.playingFileName == sound.fileName)
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
            errorMessage = "ファイルへのアクセスが拒否されました"
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
