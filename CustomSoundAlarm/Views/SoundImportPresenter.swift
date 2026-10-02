import SwiftUI
import UniformTypeIdentifiers

/// 取り込み提示（動画シート / ファイル選択 / 音声クロップ）を再利用可能にした ViewModifier（#101 B）。
/// SoundSelectionView と AlarmDetailView の両方で同じ modifier を使い、提示場所だけを変える。
/// 中身の処理（handleImport / importSound / supportedTypes）は SoundSelectionView から
/// そのまま切り出したもので、挙動は変えない。
struct SoundImportModifier: ViewModifier {
    @Binding var selectedSound: AlarmSound?
    @Binding var isImporting: Bool
    @Binding var pendingAudio: PendingAudioImport?
    @Binding var showingVideoImport: Bool
    @Binding var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: Self.supportedTypes,
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .sheet(item: $pendingAudio) { pending in
                NavigationStack {
                    AudioCropView(source: pending, selectedSound: $selectedSound)
                }
                .interactiveDismissDisabled()
            }
            .sheet(isPresented: $showingVideoImport) {
                NavigationStack {
                    VideoImportFlow(selectedSound: $selectedSound)
                }
                .interactiveDismissDisabled()
            }
    }

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
            name: SoundNameFormatter.sanitizedFileName(url.lastPathComponent)
        )
    }
}

extension View {
    func soundImport(
        selectedSound: Binding<AlarmSound?>,
        isImporting: Binding<Bool>,
        pendingAudio: Binding<PendingAudioImport?>,
        showingVideoImport: Binding<Bool>,
        errorMessage: Binding<String?>
    ) -> some View {
        modifier(SoundImportModifier(
            selectedSound: selectedSound,
            isImporting: isImporting,
            pendingAudio: pendingAudio,
            showingVideoImport: showingVideoImport,
            errorMessage: errorMessage
        ))
    }
}
