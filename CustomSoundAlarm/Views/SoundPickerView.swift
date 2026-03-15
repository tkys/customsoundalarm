import SwiftUI
import UniformTypeIdentifiers

/// 音源追加画面
/// - Files appから音声ファイルを選択（MP3, AAC, WAV, M4A, CAF）
/// - マイク録音（将来Phase）
struct SoundPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var soundStore = SoundStore.shared
    @State private var isImporting = false
    @State private var isConverting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                // MARK: - ファイル読み込み
                Section {
                    Button {
                        isImporting = true
                    } label: {
                        Label("音声ファイルを選択", systemImage: "doc.badge.plus")
                    }
                    .disabled(isConverting)
                } footer: {
                    Text("対応形式: MP3, AAC, WAV, M4A, CAF")
                }

                // MARK: - 録音（Phase 2）
                Section {
                    Label("録音する", systemImage: "mic")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("まもなく対応予定")
                }

                // MARK: - 変換中
                if isConverting {
                    Section {
                        HStack {
                            ProgressView()
                            Text("変換中...")
                                .padding(.leading, 8)
                        }
                    }
                }

                // MARK: - エラー
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("サウンドを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: Self.supportedTypes,
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
        }
    }

    // 対応する音声ファイルタイプ
    private static let supportedTypes: [UTType] = [
        .mp3,
        .aiff,
        .wav,
        .mpeg4Audio,
        UTType("com.apple.coreaudio-format") ?? .audio, // CAF
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
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
