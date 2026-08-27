import SwiftUI
import AVFoundation

/// 音声ファイル取り込みの保留状態（temp コピー済み・#77）
struct PendingAudioImport: Identifiable {
    let id = UUID()
    /// security scope を解放済みの一時コピー
    let url: URL
    let name: String
}

/// 音声ファイル用の波形クロップ画面（#77）。
/// 動画と同じ波形UIを通す。ただし**クロップは強制しない**:
/// 「全体を取り込む」で従来通りファイル全体を取り込める
/// （1分超の音源をそのまま使う需要が実在するため）。
struct AudioCropView: View {
    let source: PendingAudioImport
    @Binding var selectedSound: AlarmSound?
    @Environment(\.dismiss) private var dismiss
    @State private var soundStore = SoundStore.shared

    @State private var duration: Double = 0
    @State private var startTime: Double = 0
    @State private var endTime: Double = 0
    @State private var soundName = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?

    // プレビュー再生
    @State private var previewer = TrimPreviewer()

    var body: some View {
        Form {
            // 1. 波形クロップ + 試聴
            Section {
                VStack(spacing: 12) {
                    if duration > 0 {
                        WaveformCropView(
                            startTime: $startTime,
                            endTime: $endTime,
                            audioURL: source.url,
                            duration: duration,
                            maxRange: max(duration, 1),  // 音声は無上限（v1.5.0）
                            previewer: previewer,
                            playURL: source.url
                        )
                    } else {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("waveform_loading")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                    }

                    // プレビューボタン
                    HStack {
                        Button {
                            if previewer.isPlaying {
                                previewer.stop()
                            } else {
                                previewer.play(url: source.url, from: startTime, to: endTime)
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
                        .disabled(duration <= 0)

                        Spacer()

                        if previewer.isPlaying {
                            Text(WaveformCropMath.formatTime(previewer.currentTime - startTime) + " / " + WaveformCropMath.formatTime(endTime - startTime))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }

                    // 変換後サイズの見積りと警告（#79-8）
                    sizeEstimateRow
                }
                .padding(.vertical, 4)
            } header: {
                WarmSectionHeader(title: String(localized: "range"))
            } footer: {
                Text("crop_hint_footer")
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

            // 3. 保存ボタン（切り出し / 全体）
            Section {
                Button {
                    save(start: startTime, end: endTime)
                } label: {
                    HStack {
                        Spacer()
                        if isProcessing {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("converting")
                        } else {
                            Label("crop_and_save", systemImage: "waveform.badge.plus")
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
                            (isProcessing || !canSave)
                                ? AnyShapeStyle(Color.gray.opacity(0.4))
                                : AnyShapeStyle(Brand.saveButtonGradient)
                        )
                        .padding(.horizontal, 4)
                )
                .disabled(isProcessing || !canSave)

                // クロップを強制しない: 全体取り込みの選択肢（#77）
                Button {
                    save(start: 0, end: duration)
                } label: {
                    HStack {
                        Spacer()
                        Label("import_whole_audio", systemImage: "tray.and.arrow.down")
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
                .disabled(isProcessing || !canSave)
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
        .navigationTitle(String(localized: "add_from_audio"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDuration()
        }
        .onDisappear {
            previewer.stop()
        }
    }

    // MARK: - State

    private var canSave: Bool {
        duration > 0 && endTime > startTime && !soundName.isEmpty
    }

    /// 変換後のサイズ見積り。音声は尺無制限のため生成前に見せる（#79-8）
    private var sizeEstimateRow: some View {
        let selectionSeconds = endTime - startTime
        let size = AudioSizeEstimate.formattedSize(
            bytes: AudioSizeEstimate.estimatedFileSize(seconds: selectionSeconds)
        )
        return VStack(spacing: 4) {
            Text(String(format: String(localized: "estimated_size"), size))
                .font(.caption2)
                .foregroundStyle(.secondary)
            if AudioSizeEstimate.requiresWarning(seconds: selectionSeconds) {
                Text(String(format: String(localized: "large_file_warning"), size))
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func loadDuration() async {
        let asset = AVURLAsset(url: source.url)
        guard let cmDuration = try? await asset.load(.duration) else {
            errorMessage = String(localized: "file_load_failed")
            return
        }
        let seconds = CMTimeGetSeconds(cmDuration)
        guard seconds.isFinite, seconds > 0 else {
            errorMessage = String(localized: "file_load_failed")
            return
        }
        duration = seconds
        // 初期選択は全範囲（音声は上限なし）
        startTime = 0
        endTime = seconds
        if soundName.isEmpty {
            soundName = source.name
        }
    }

    // MARK: - Save

    private func save(start: Double, end: Double) {
        isProcessing = true
        errorMessage = nil
        previewer.stop()

        Task {
            defer { isProcessing = false }

            do {
                let fileName = try await AudioConverter.shared.convertToCAF(
                    from: source.url,
                    outputName: UUID().uuidString,
                    startTime: start > 0 ? start : nil,
                    endTime: end < duration ? end : nil
                )

                let sound = AlarmSound(name: soundName, fileName: fileName)
                soundStore.add(sound)
                selectedSound = sound

                AnalyticsService.shared.capture(.customSoundImported(source: .audio))

                // 一時コピーを破棄して閉じる
                try? FileManager.default.removeItem(at: source.url)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}