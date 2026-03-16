import SwiftUI
import AVFoundation
import PhotosUI

/// 動画から音声を抽出するフロー
/// PhotosPicker → トリム → 抽出 → CAF変換
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
    @State private var showingPicker = false

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
        .onAppear { showingPicker = videoURL == nil }
        .onDisappear { previewer.stop() }
        .photosPicker(
            isPresented: $showingPicker,
            selection: $selectedItem,
            matching: .videos
        )
        .onChange(of: selectedItem) { _, newItem in
            if let newItem {
                loadVideo(from: newItem)
            }
        }
        .onChange(of: showingPicker) { _, isPresented in
            if !isPresented && videoURL == nil && selectedItem == nil {
                dismiss()
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
    private var durationExceeds30s: Bool { selectedDuration > 30 }

    private func trimView(url: URL) -> some View {
        Form {
            // 1. 試聴 + タイムライン
            Section {
                VStack(spacing: 12) {
                    // タイムライン表示（再生位置インジケーター付き）
                    timelineBar

                    // タイムラインマーカー
                    HStack {
                        Text(formatTime(startTime))
                        Spacer()
                        Text(String(format: String(localized: "selected_duration"), formatTime(selectedDuration)))
                            .foregroundStyle(durationExceeds30s ? .orange : Color.accentColor)
                            .fontWeight(.medium)
                        Spacer()
                        Text(formatTime(endTime))
                    }
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

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
                WarmSectionHeader(title: String(localized: "preview"))
            }

            // 2. 範囲選択
            Section {
                VStack(spacing: 12) {
                    LabeledContent {
                        Text(formatTime(startTime))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } label: {
                        Text("start")
                    }
                    Slider(
                        value: $startTime,
                        in: 0...max(videoDuration - 1, 0)
                    ) {
                        Text("start")
                    } onEditingChanged: { editing in
                        if !editing && endTime <= startTime {
                            endTime = min(startTime + 30, videoDuration)
                        }
                        if editing { previewer.stop() }
                    }

                    Divider()

                    LabeledContent {
                        Text(formatTime(endTime))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } label: {
                        Text("end")
                    }
                    Slider(
                        value: $endTime,
                        in: 0...videoDuration
                    ) {
                        Text("end")
                    } onEditingChanged: { editing in
                        if !editing && endTime <= startTime {
                            startTime = max(endTime - 30, 0)
                        }
                        if editing { previewer.stop() }
                    }
                    .tint(durationExceeds30s ? .orange : nil)
                }
                .padding(.vertical, 4)
            } header: {
                WarmSectionHeader(title: String(localized: "range"))
            } footer: {
                if durationExceeds30s {
                    Text("duration_warning")
                        .foregroundStyle(.orange)
                } else {
                    Text(String(format: String(localized: "total_duration"), formatTime(videoDuration)))
                }
            }

            // 3. サウンド名
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

            // 4. 保存ボタン
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

    // MARK: - Timeline Bar

    private var timelineBar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let startFraction = videoDuration > 0 ? startTime / videoDuration : 0
            let endFraction = videoDuration > 0 ? endTime / videoDuration : 1
            let leading = width * startFraction
            let selectedWidth = width * (endFraction - startFraction)

            ZStack(alignment: .leading) {
                // 全体バー（inner shadow effect）
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.08), lineWidth: 1)
                    )
                    .frame(height: 40)

                // 選択範囲（warm gradient）
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.3),
                                Color.accentColor.opacity(0.15)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: max(selectedWidth, 2), height: 40)
                    .offset(x: leading)

                // 選択範囲の枠線
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5)
                    .frame(width: max(selectedWidth, 2), height: 40)
                    .offset(x: leading)

                // 左ハンドル
                handleMark(at: leading)

                // 右ハンドル
                handleMark(at: leading + selectedWidth)

                // 再生位置インジケーター
                if previewer.isPlaying, videoDuration > 0 {
                    let playFraction = previewer.currentTime / videoDuration
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.red)
                        .frame(width: 2.5, height: 30)
                        .offset(x: width * playFraction)
                        .shadow(color: .red.opacity(0.4), radius: 3)
                }
            }
        }
        .frame(height: 40)
    }

    private func handleMark(at x: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.accentColor)
            .frame(width: 3, height: 24)
            .offset(x: x)
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

    private func extractAndConvert(from url: URL) {
        isProcessing = true
        errorMessage = nil

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
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
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
