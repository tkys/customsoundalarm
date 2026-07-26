import SwiftUI
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

/// 動画から音声を抽出するフロー
/// ソース選択（写真ライブラリ / ファイル）→ トリム → 抽出 → CAF変換
struct VideoImportFlow: View {
    @Binding var selectedSound: AlarmSound?
    @Environment(\.dismiss) private var dismiss
    @State private var soundStore = SoundStore.shared

    @State private var selectedItem: PhotosPickerItem?
    @State private var videoURL: URL?
    @State private var videoDuration: Double = 0
    @State private var startTime: Double = 0
    @State private var endTime: Double = 30
    @State private var soundName = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showingSourceDialog = false
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false

    // インポートソース（計測用）
    @State private var importSource: VideoImportSource = .photoLibrary

    // プレビュー再生
    @State private var previewer = TrimPreviewer()

    var body: some View {
        Group {
            if let videoURL {
                trimView(url: videoURL)
            } else {
                loadingView
            }
        }
        .navigationTitle(String(localized: "add_from_video_title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if videoURL == nil { showingSourceDialog = true }
        }
        .onDisappear { previewer.stop() }
        // ソース選択ダイアログ
        .confirmationDialog(
            String(localized: "video_source_title"),
            isPresented: $showingSourceDialog,
            titleVisibility: .visible
        ) {
            Button(String(localized: "video_source_photo")) {
                showingPhotoPicker = true
                importSource = .photoLibrary
            }
            Button(String(localized: "video_source_file")) {
                showingFilePicker = true
                importSource = .file
            }
            Button("cancel", role: .cancel) {
                if videoURL == nil { dismiss() }
            }
        }
        // 写真ライブラリ
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedItem,
            matching: .videos
        )
        .onChange(of: selectedItem) { _, newItem in
            if let newItem {
                loadVideo(from: newItem)
            }
        }
        // ファイル（iCloud Drive / 他アプリ）
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: VideoFileImporter.supportedVideoTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                loadVideoFromFile(url: url)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .onChange(of: showingPhotoPicker) { _, isPresented in
            if !isPresented && videoURL == nil && selectedItem == nil && !showingFilePicker {
                showingSourceDialog = true
            }
        }
        .onChange(of: showingFilePicker) { _, isPresented in
            if !isPresented && videoURL == nil && !showingPhotoPicker {
                showingSourceDialog = true
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            if isProcessing {
                ProgressView()
                Text("loading")
                    .foregroundStyle(.secondary)
            } else if let errorMessage {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("select_video")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Trim View

    private var selectedDuration: Double { endTime - startTime }

    private func trimView(url: URL) -> some View {
        Form {
            // 1. トリムバー + 試聴
            Section {
                VStack(spacing: 12) {
                    VideoTrimmerBar(
                        startTime: $startTime,
                        endTime: $endTime,
                        videoURL: url,
                        videoDuration: videoDuration,
                        previewer: previewer
                    )

                    // プレビューボタン
                    HStack {
                        Button {
                            if previewer.isPlaying {
                                previewer.stop()
                            } else {
                                previewer.play(url: url, from: startTime, to: endTime)
                            }
                        } label: {
                            Label(
                                previewer.isPlaying ? String(localized: "stop") : String(localized: "preview_selection"),
                                systemImage: previewer.isPlaying ? "stop.fill" : "play.fill"
                            )
                            .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .tint(previewer.isPlaying ? .red : .accentColor)

                        Spacer()

                        if previewer.isPlaying {
                            Text(formatTime(previewer.currentTime - startTime) + " / " + formatTime(selectedDuration))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                WarmSectionHeader(title: String(localized: "range"))
            } footer: {
                Text(String(format: String(localized: "total_duration"), formatTime(videoDuration)))
            }

            // 2. サウンド名
            Section {
                HStack {
                    Text("name")
                    TextField("sound_name_placeholder", text: $soundName)
                        .multilineTextAlignment(.trailing)
                }
            } footer: {
                if soundName.isEmpty {
                    Text("enter_name_to_save")
                }
            }

            // 3. 保存ボタン
            Section {
                Button {
                    previewer.stop()
                    extractAndConvert(from: url)
                } label: {
                    HStack {
                        Spacer()
                        if isProcessing {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("converting")
                        } else {
                            Label("extract_and_save", systemImage: "waveform.badge.plus")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .foregroundStyle(.white)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            (isProcessing || endTime <= startTime || soundName.isEmpty)
                                ? AnyShapeStyle(Color.gray.opacity(0.4))
                                : AnyShapeStyle(Brand.saveButtonGradient)
                        )
                        .padding(.horizontal, 4)
                )
                .disabled(isProcessing || endTime <= startTime || soundName.isEmpty)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .warmListBackground()
    }

    // MARK: - Actions

    private func loadVideo(from item: PhotosPickerItem) {
        isProcessing = true
        errorMessage = nil

        Task {
            defer { isProcessing = false }

            do {
                guard let movie = try await item.loadTransferable(type: VideoTransferable.self) else {
                    errorMessage = String(localized: "file_load_failed")
                    return
                }

                let duration = try await VideoAudioExtractor.shared.getDuration(from: movie.url)
                videoDuration = duration
                endTime = min(30, duration)
                videoURL = movie.url
                soundName = movie.url.deletingPathExtension().lastPathComponent
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// `.fileImporter` 経由で選択された動画を読み込む。
    /// security-scoped resource の寿命を最小化するため、
    /// 選択直後に temp へコピー → 即解放する（罠1 対策）。
    /// iCloud Drive の未ダウンロードファイルは NSFileCoordinator が待機する（罠2 対策）。
    private func loadVideoFromFile(url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = String(localized: "error_file_access_denied")
            return
        }

        isProcessing = true
        errorMessage = nil

        Task {
            // 罠1: temp コピー完了直後に security scope を解放。
            // 重い処理（duration 取得・抽出）は temp URL で行う。
            let tempURL: URL
            do {
                tempURL = try await VideoFileImporter.copyToTemp(from: url)
            } catch {
                url.stopAccessingSecurityScopedResource()
                await MainActor.run {
                    isProcessing = false
                    errorMessage = error.localizedDescription
                }
                return
            }
            url.stopAccessingSecurityScopedResource()

            do {
                let duration = try await VideoAudioExtractor.shared.getDuration(from: tempURL)
                await MainActor.run {
                    videoDuration = duration
                    endTime = min(30, duration)
                    videoURL = tempURL
                    soundName = tempURL.deletingPathExtension().lastPathComponent
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func extractAndConvert(from url: URL) {
        isProcessing = true
        errorMessage = nil

        AnalyticsService.shared.capture(.videoImportStarted(source: importSource))

        Task {
            defer { isProcessing = false }

            do {
                let audioURL = try await VideoAudioExtractor.shared.extractAudio(
                    from: url,
                    startTime: startTime,
                    endTime: endTime
                )

                let cafName = try await AudioConverter.shared.convertToCAF(
                    from: audioURL,
                    outputName: UUID().uuidString
                )

                try? FileManager.default.removeItem(at: audioURL)

                let sound = AlarmSound(
                    name: soundName.isEmpty ? url.deletingPathExtension().lastPathComponent : soundName,
                    fileName: cafName
                )
                soundStore.add(sound)
                selectedSound = sound

                AnalyticsService.shared.capture(.customSoundImported(source: .video))
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                // 計測: reason は安定識別子のみ（PII/パス混入を避けるため localizedDescription 不使用）
                AnalyticsService.shared.capture(.videoImportFailed(reason: .from(error)))
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - TrimPreviewer

/// 選択範囲のプレビュー再生を管理
@Observable
@MainActor
final class TrimPreviewer {
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var boundaryObserver: Any?

    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0

    func play(url: URL, from start: Double, to end: Double) {
        stop()

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            return
        }

        let playerItem = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: playerItem)

        // 開始位置にシーク
        let startCMTime = CMTime(seconds: start, preferredTimescale: 600)
        avPlayer.seek(to: startCMTime, toleranceBefore: .zero, toleranceAfter: .zero)

        // 定期的に再生位置を更新（UIアニメーション用）
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = CMTimeGetSeconds(time)
            }
        }

        // 終了位置で自動停止
        let endCMTime = CMTime(seconds: end, preferredTimescale: 600)
        boundaryObserver = avPlayer.addBoundaryTimeObserver(
            forTimes: [NSValue(time: endCMTime)],
            queue: .main
        ) { [weak self] in
            Task { @MainActor in
                self?.stop()
            }
        }

        self.player = avPlayer
        avPlayer.play()
        isPlaying = true
        currentTime = start
    }

    func stop() {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        if let boundaryObserver {
            player?.removeTimeObserver(boundaryObserver)
        }
        timeObserver = nil
        boundaryObserver = nil
        player?.pause()
        player = nil
        isPlaying = false
        currentTime = 0
    }
}

// MARK: - VideoTransferable

struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: tempURL)
            return Self(url: tempURL)
        }
    }
}
