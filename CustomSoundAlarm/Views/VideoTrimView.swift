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
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let videoURL {
                trimView(url: videoURL)
            } else {
                loadingView
            }
        }
        .navigationTitle("動画から音声を追加")
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(
            isPresented: .constant(videoURL == nil && !isProcessing),
            selection: $selectedItem,
            matching: .videos
        )
        .onChange(of: selectedItem) { _, newItem in
            if let newItem {
                loadVideo(from: newItem)
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            if isProcessing {
                ProgressView()
                Text("読み込み中...")
                    .foregroundStyle(.secondary)
            } else if let errorMessage {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("動画を選択してください")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Trim View

    private func trimView(url: URL) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("使用する範囲を選択")
                        .font(.headline)

                    HStack {
                        Text(formatTime(startTime))
                            .monospacedDigit()
                        Spacer()
                        Text(formatTime(endTime))
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    // 開始位置
                    VStack(alignment: .leading) {
                        Text("開始: \(formatTime(startTime))")
                            .font(.caption)
                        Slider(
                            value: $startTime,
                            in: 0...max(videoDuration - 1, 0)
                        ) {
                            Text("開始")
                        } onEditingChanged: { _ in
                            if endTime <= startTime {
                                endTime = min(startTime + 30, videoDuration)
                            }
                        }
                    }

                    // 終了位置
                    VStack(alignment: .leading) {
                        Text("終了: \(formatTime(endTime))")
                            .font(.caption)
                        Slider(
                            value: $endTime,
                            in: 0...videoDuration
                        ) {
                            Text("終了")
                        } onEditingChanged: { _ in
                            if endTime <= startTime {
                                startTime = max(endTime - 30, 0)
                            }
                        }
                    }

                    Text("選択範囲: \(formatTime(endTime - startTime))")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.vertical, 4)
            } footer: {
                Text("アラーム音は30秒以内を推奨")
            }

            Section {
                Button {
                    extractAndConvert(from: url)
                } label: {
                    if isProcessing {
                        HStack {
                            ProgressView()
                            Text("変換中...")
                                .padding(.leading, 8)
                        }
                    } else {
                        Label("音声を抽出して保存", systemImage: "waveform.badge.plus")
                    }
                }
                .disabled(isProcessing || endTime <= startTime)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadVideo(from item: PhotosPickerItem) {
        isProcessing = true
        errorMessage = nil

        Task {
            defer { isProcessing = false }

            do {
                // PhotosPickerItemから動画URLを取得
                guard let movie = try await item.loadTransferable(type: VideoTransferable.self) else {
                    errorMessage = "動画の読み込みに失敗しました"
                    return
                }

                let duration = try await VideoAudioExtractor.shared.getDuration(from: movie.url)
                videoDuration = duration
                endTime = min(30, duration)
                videoURL = movie.url
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
                // 動画から音声抽出
                let audioURL = try await VideoAudioExtractor.shared.extractAudio(
                    from: url,
                    startTime: startTime,
                    endTime: endTime
                )

                // CAF変換
                let cafName = try await AudioConverter.shared.convertToCAF(
                    from: audioURL,
                    outputName: UUID().uuidString
                )

                // クリーンアップ
                try? FileManager.default.removeItem(at: audioURL)

                let sound = AlarmSound(
                    name: url.deletingPathExtension().lastPathComponent,
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
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
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
