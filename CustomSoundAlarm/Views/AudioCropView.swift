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

    /// 編集内容の破棄確認（#82-2: 閉じる操作で黙って消えないようにする）
    @State private var showingDiscardConfirm = false

    // プレビュー再生
    @State private var previewer = TrimPreviewer()

    var body: some View {
        VStack(spacing: 0) {
            // 波形エリア（画面幅いっぱい・#80-1）。フォームの体裁を使わない
            ScrollView {
                VStack(spacing: 14) {
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

                    // 再生 / 停止（スクラブと対の操作）
                    Button {
                        if previewer.isPlaying {
                            previewer.stop()
                        } else {
                            previewer.play(url: source.url, from: startTime, to: endTime)
                        }
                    } label: {
                        Image(systemName: previewer.isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .background(
                                Circle().fill(Color.accentColor.opacity(0.14))
                            )
                            .foregroundStyle(previewer.isPlaying ? Color.red : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(duration <= 0)
                    .accessibilityLabel(previewer.isPlaying ? String(localized: "stop") : String(localized: "preview_selection"))

                    // 変換後サイズの見積りと警告（#79-8）
                    sizeEstimateRow
                        .padding(.horizontal, 20)

                    Text("crop_hint_footer")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)

            Spacer(minLength: 0)

            // 下部: 名前入力 + アクション
            VStack(spacing: 10) {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundStyle(Color.accentColor)
                    TextField("sound_name_placeholder", text: $soundName)
                        .textFieldStyle(.plain)
                        .submitLabel(.done)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.warmCardBackground)
                )

                // 主アクション: 目立つ pill ボタン（#80-7）
                Button {
                    save(start: startTime, end: endTime)
                } label: {
                    HStack(spacing: 8) {
                        if isProcessing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "waveform.badge.plus")
                        }
                        Text("crop_and_save")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule().fill(
                            (isProcessing || !canSave)
                                ? AnyShapeStyle(Color.gray.opacity(0.4))
                                : AnyShapeStyle(Brand.saveButtonGradient)
                        )
                    )
                    .foregroundStyle(.white)
                }
                .disabled(isProcessing || !canSave)

                // 副アクション: 格下のテキストボタン（クロップを強制しない・#77/#80-7）
                Button {
                    save(start: 0, end: duration)
                } label: {
                    Label("import_whole_audio", systemImage: "tray.and.arrow.down")
                        .font(.footnote)
                }
                .buttonStyle(.borderless)
                .tint(.secondary)
                .disabled(isProcessing || !canSave)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(Color.warmListBackground.ignoresSafeArea())
        .navigationTitle(String(localized: "add_from_audio"))
        .navigationBarTitleDisplayMode(.inline)
        // 閉じるボタン（#82-2: 誤クローズ防止の代替出口。編集中は破棄を確認する）
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if duration > 0 {
                        showingDiscardConfirm = true
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(String(localized: "close"))
            }
        }
        // 編集内容の破棄確認（#82-2）
        .confirmationDialog(
            String(localized: "discard_edits_title"),
            isPresented: $showingDiscardConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "discard"), role: .destructive) {
                previewer.stop()
                // 一時コピーを破棄して閉じる
                try? FileManager.default.removeItem(at: source.url)
                dismiss()
            }
            Button("cancel", role: .cancel) {}
        } message: {
            Text("discard_edits_message")
        }
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

                // サムネイル: 埋め込みアートワーク（ID3 / MP4 メタデータ・#86）。
                // 無い素の音声は nil（波形の代替表示にフォールバック）
                let thumbnailFileName = await SoundThumbnailStore.shared
                    .artwork(from: source.url)
                    .flatMap { SoundThumbnailStore.shared.save($0) }

                let sound = AlarmSound(name: soundName, fileName: fileName, thumbnailFileName: thumbnailFileName)
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