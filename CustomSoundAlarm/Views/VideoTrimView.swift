import SwiftUI
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

/// 動画から音声を抽出するフロー
/// ソース選択（写真ライブラリ / ファイル）→ トリム → 抽出 → CAF変換
struct VideoImportFlow: View {
    @Binding var selectedSound: AlarmSound?
    /// 共有シートから渡された動画（#222）。指定時はソース選択を飛ばす。
    var initialFileURL: URL?
    /// 共有シートが控えた表示名（#239）
    var initialSoundName: String?
    /// 計測用の取り込み経路（共有シートは .share・#222）
    var customSoundSource: SoundImportSource = .video
    /// 共有経路の種類（#222）
    var shareMedia: ShareImportMedia?
    /// 保存できたとき（共有シートの staging を消す・#222）
    var onSaved: (() -> Void)?
    /// ユーザーが × で閉じたとき（共有シートの staging を消す・#222）
    var onUserClosed: (() -> Void)?
    @Binding var volumeBoostedFileName: String?
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
    @State private var silentLevel: SilentSoundLevel?
    @State private var silentCoversWholeFile = false
    @State private var pendingSilentSave: PendingVideoSave?

    private struct PendingVideoSave {
        let result: ConversionResult
        let cafName: String
        let thumbnailFileName: String?
        let audioURL: URL
    }
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false

    /// 編集内容の破棄確認（#82-2: 閉じる操作で黙って消えないようにする）
    @State private var showingDiscardConfirm = false

    /// 波形描画・試聴・切り出しの元になる音声（動画から抽出済みの一時m4a）。
    /// 抽出完了までクロップUIはプレースホルダを表示する（#77）
    @State private var extractedAudioURL: URL?
    /// 共有で渡された動画を一度だけ読む（#222）
    @State private var didLoadInitialFile = false

    // インポートソース（計測用）
    @State private var importSource: VideoImportSource = .photoLibrary

    // プレビュー再生
    @State private var previewer = TrimPreviewer()

    /// 切り出し上限（VideoTrimmerBar と同じ値）
    private let maxRangeSeconds: Double = 600

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .frame(height: 1)
                .accessibilityIdentifier("videoImport.root")
            Group {
                if let videoURL {
                    trimView(url: videoURL)
                } else {
                    sourceSelectionView
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            AdSlot(slot: .bannerImport)
        }
        .navigationTitle(String(localized: "add_from_video_title"))
        .navigationBarTitleDisplayMode(.inline)
        // 閉じるボタン（#82-2: シート化に伴う明示的な出口。編集中は破棄を確認する）
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if videoURL != nil {
                        showingDiscardConfirm = true
                    } else {
                        onUserClosed?()
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
                onUserClosed?()
                dismiss()
            }
            Button("cancel", role: .cancel) {}
        } message: {
            Text("discard_edits_message")
        }
        .task {
            guard !didLoadInitialFile, let initialFileURL else { return }
            didLoadInitialFile = true
            loadVideoFromFile(url: initialFileURL)
        }
        .onDisappear {
            previewer.stop()
            // 無音の知らせを出したまま閉じたときの取りこぼしを消す（#256）
            deletePendingFile()
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
    }

    // MARK: - Source selection

    /// 動画が未選択のあいだの2行（#200）。標準のダイアログは使わない。
    private var sourceSelectionView: some View {
        List {
            Section {
                sourceRow(
                    title: "video_source_photo_row",
                    systemImage: "photo.on.rectangle",
                    identifier: "videoImport.source.photo"
                ) {
                    // 同じ動画を選び直しても onChange が発火するように消してから開く（#200 レビュー）
                    selectedItem = nil
                    importSource = .photoLibrary
                    showingPhotoPicker = true
                }
                .disabled(isProcessing)

                sourceRow(
                    title: "video_source_file_row",
                    systemImage: "folder",
                    identifier: "videoImport.source.file"
                ) {
                    importSource = .file
                    showingFilePicker = true
                }
                .disabled(isProcessing)
            } header: {
                WarmSectionHeader(title: String(localized: "video_source_header"))
            }

            if isProcessing || errorMessage != nil {
                Section {
                    loadingStatus
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
        }
        .warmListBackground()
    }

    private func sourceRow(
        title: LocalizedStringKey,
        systemImage: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.actionText)
                    .padding(4)
                    .background(
                        Circle()
                            .fill(Color.actionText.opacity(0.12))
                    )
            }
        }
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Loading

    /// 読み込み中・エラーの表示。2行はこの下でも押せる（#200）。
    @ViewBuilder
    private var loadingStatus: some View {
        if isProcessing {
            VStack(spacing: 12) {
                ProgressView()
                Text("loading")
                    .foregroundStyle(Color.textSecondary)
            }
        } else if let errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text(errorMessage)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Trim View

    /// 「この範囲を追加」が押せる条件
    private var canSave: Bool {
        extractedAudioURL != nil && endTime > startTime && !soundName.isEmpty
    }

    /// 波形UIの選択範囲（再生のくり返しにも使う・#303）
    private var currentTrimRange: TrimRange {
        TrimRange(
            start: startTime,
            end: endTime,
            duration: videoDuration,
            maxRange: maxRangeSeconds
        )
    }

    private func trimView(url: URL) -> some View {
        VStack(spacing: 0) {
            // 波形エリア（画面幅いっぱい・#80-1）。フォームの体裁を使わない
            ScrollView {
                VStack(spacing: 14) {
                    if let audioURL = extractedAudioURL {
                        // 波形を主・サムネイルを補助とする二段構えのクロップUI（#77）
                        WaveformCropView(
                            startTime: $startTime,
                            endTime: $endTime,
                            audioURL: audioURL,
                            duration: videoDuration,
                            maxRange: maxRangeSeconds,
                            previewer: previewer,
                            playURL: audioURL
                        )
                    } else {
                        // 音声抽出中のプレースホルダ（UIはブロックしない）
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("waveform_loading")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                    }

                    // 補助: サムネイル（通常の動画では位置の手がかりになる）
                    FilmstripView(videoURL: url)

                    // 再生 / 停止（選択範囲をくり返し鳴らす・#303）
                    Button {
                        if previewer.isPlaying {
                            previewer.stop()
                        } else {
                            let range = currentTrimRange
                            previewer.play(
                                url: extractedAudioURL ?? url,
                                range: range,
                                from: previewer.resumeTime(in: range)
                            )
                        }
                    } label: {
                        Image(systemName: previewer.isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .background(
                                Circle().fill(Color.actionText.opacity(0.14))
                            )
                            .foregroundStyle(previewer.isPlaying ? Color.red : Color.actionText)
                    }
                    .buttonStyle(.plain)
                    .disabled(extractedAudioURL == nil)
                    .accessibilityLabel(previewer.isPlaying ? String(localized: "stop") : String(localized: "preview_selection"))

                    // 変換後サイズの見積りと警告（#79-8）
                    sizeEstimateRow
                        .padding(.horizontal, 20)

                    Text("crop_hint_footer")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
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
                if let silentLevel {
                    SilentSoundNoticeView(
                        level: silentLevel,
                        isWholeFileSilent: silentCoversWholeFile,
                        onReselect: { handleSilentAction(.reselect) },
                        onOtherSound: { handleSilentAction(.otherSound) },
                        onUseAnyway: { handleSilentAction(.useAnyway) }
                    )
                } else {
                    nameAndSaveControls(url: url)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(Color.warmListBackground.ignoresSafeArea())
        // 動画が選び直されたら波形用音声を抽出し直す
        .task(id: url) {
            await extractAudioForWaveform(from: url)
        }
    }

    // MARK: - Actions

    /// duration に応じた初期選択範囲（全長 ≤ 上限なら全体、超えるなら先頭から上限分）
    private func applyFullRange(duration: Double) {
        let full = TrimRange.fullRange(duration: duration, maxRange: maxRangeSeconds)
        startTime = full.start
        endTime = full.end
    }

    /// 波形描画・試聴・切り出しの元として音声を一度だけ抽出する（#77）。
    /// AVAudioFile ベースの波形解析は動画コンテナを読めないため、
    /// 先に m4a へ抽出してから波形を出す方針。抽出中はプレースホルダを表示。
    private func extractAudioForWaveform(from url: URL) async {
        if let old = extractedAudioURL {
            try? FileManager.default.removeItem(at: old)
        }
        extractedAudioURL = nil
        do {
            let audio = try await VideoAudioExtractor.shared.extractAudio(from: url)
            if !Task.isCancelled {
                extractedAudioURL = audio
            } else {
                try? FileManager.default.removeItem(at: audio)
            }
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadVideo(from item: PhotosPickerItem) {
        isProcessing = true
        errorMessage = nil
        // 失敗しても同じ動画を選び直せるように、読み取り後は選択を空に戻す（#200 レビュー）
        selectedItem = nil

        Task {
            defer { isProcessing = false }

            do {
                guard let movie = try await item.loadTransferable(type: VideoTransferable.self) else {
                    errorMessage = String(localized: "file_load_failed")
                    return
                }

                let duration = try await VideoAudioExtractor.shared.getDuration(from: movie.url)
                videoDuration = duration
                applyFullRange(duration: duration)
                videoURL = movie.url
                soundName = movie.displayName
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
        // 共有シートの staging はアプリ所有なので security scope は不要（#222）
        let didStartSecurityScope = url.startAccessingSecurityScopedResource()

        // temp コピー前に元ファイル名を控える（temp URL は UUID になるため）
        let originalName = VideoFileImporter.initialSoundName(
            sharedDisplayName: initialSoundName,
            fileURL: url
        )

        isProcessing = true
        errorMessage = nil

        Task {
            // 罠1: temp コピー完了直後に security scope を解放。
            // 重い処理（duration 取得・抽出）は temp URL で行う。
            let tempURL: URL
            do {
                tempURL = try await VideoFileImporter.copyToTemp(from: url)
            } catch {
                if didStartSecurityScope { url.stopAccessingSecurityScopedResource() }
                await MainActor.run {
                    isProcessing = false
                    errorMessage = error.localizedDescription
                }
                return
            }
            if didStartSecurityScope { url.stopAccessingSecurityScopedResource() }

            do {
                let duration = try await VideoAudioExtractor.shared.getDuration(from: tempURL)
                await MainActor.run {
                    videoDuration = duration
                    applyFullRange(duration: duration)
                    videoURL = tempURL
                    soundName = originalName
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

    /// 元動画からサムネイルを生成して保存し、ファイル名を返す（#86）。
    /// 失敗（映像なし等）は nil（プリセット/波形の代替表示にフォールバック）
    private static func generateThumbnail(videoURL: URL) async -> String? {
        guard let frame = await SoundThumbnailStore.shared.bestVideoFrame(from: videoURL) else {
            return nil
        }
        return SoundThumbnailStore.shared.save(frame)
    }

    private func extractAndConvert(from url: URL) {
        guard let audioURL = extractedAudioURL else { return }
        isProcessing = true
        errorMessage = nil

        AnalyticsService.shared.capture(.videoImportStarted(source: importSource))

        Task {
            defer { isProcessing = false }

            do {
                // 波形・試聴に使った抽出済み音声から、範囲指定で直接CAFへ変換（#77）
                let result = try await AudioConverter.shared.convertToCAF(
                    from: audioURL,
                    outputName: UUID().uuidString,
                    startTime: startTime,
                    endTime: endTime
                )
                let cafName = result.fileName

                // サムネイル: 元動画の12フレーム候補から輝度分散最大の1枚（#86）
                let thumbnailFileName = await Self.generateThumbnail(videoURL: url)

                let level = SilentSoundLogic.judge(
                    lufsBefore: result.lufsBefore,
                    peakDb: result.peakDb,
                    gainDb: result.gainDb
                )
                if level != .ok {
                    // 抽出した音声全体が無音なら、範囲を選び直しても無音（#256 レビュー）。
                    let wholeFileSilent = await Task.detached {
                        let buffer = AudioSampleLoader.loadMono44k(fileURL: audioURL)
                        return SilentSoundLogic.isWholeFileSilent(
                            measurement: buffer.flatMap { LoudnessMeter.measure(buffer: $0) },
                            isReadable: buffer != nil
                        )
                    }.value
                    pendingSilentSave = PendingVideoSave(
                        result: result,
                        cafName: cafName,
                        thumbnailFileName: thumbnailFileName,
                        audioURL: audioURL
                    )
                    silentCoversWholeFile = wholeFileSilent
                    silentLevel = level
                    return
                }

                await completeSave(
                    result: result,
                    cafName: cafName,
                    thumbnailFileName: thumbnailFileName,
                    audioURL: audioURL,
                    videoURL: url
                )
            } catch {
                errorMessage = error.localizedDescription
                // 計測: reason は安定識別子のみ（PII/パス混入を避けるため localizedDescription 不使用）
                AnalyticsService.shared.capture(.videoImportFailed(reason: .from(error)))
            }
        }
    }

    /// 無音でないことを確認したあとの保存（#256）。
    private func completeSave(
        result: ConversionResult,
        cafName: String,
        thumbnailFileName: String?,
        audioURL: URL,
        videoURL: URL
    ) async {
        try? FileManager.default.removeItem(at: audioURL)
        extractedAudioURL = nil

        let sound = AlarmSound(
            name: soundName.isEmpty
                ? videoURL.deletingPathExtension().lastPathComponent
                : soundName,
            fileName: cafName,
            thumbnailFileName: thumbnailFileName,
            lufsAtImport: result.lufsBefore,
            gainDbAtImport: result.gainDb
        )
        soundStore.add(sound)
        selectedSound = sound
        let showsVolumeNotice = LoudnessNormalizer.shouldShowVolumeNotice(
            gainDb: result.gainDb
        )
        if showsVolumeNotice {
            volumeBoostedFileName = cafName
        }

        onSaved?()
        AnalyticsService.shared.capture(.customSoundImported(
            source: customSoundSource,
            peakDbBucket: LoudnessNormalizer.peakDbBucket(forPeakDb: result.peakDb),
            gainDbBucket: LoudnessNormalizer.gainDbBucket(forGainDb: result.gainDb),
            lufsBucket: LoudnessMeter.bucket(forLufs: result.lufsBefore),
            shareMedia: shareMedia,
            volumeNoticeShown: showsVolumeNotice
        ))
        await AdPresenter.presentInterstitialIfAllowed(after: .importSaved)
        dismiss()
    }

    private func handleSilentAction(_ action: SilentSoundAction) {
        guard let level = silentLevel else { return }
        AnalyticsService.shared.capture(.silentSoundBlocked(
            level: level,
            source: customSoundSource,
            action: action
        ))

        switch action {
        case .reselect:
            deletePendingFile()
            pendingSilentSave = nil
            silentLevel = nil
            silentCoversWholeFile = false
        case .otherSound:
            deletePendingFile()
            if let pending = pendingSilentSave {
                try? FileManager.default.removeItem(at: pending.audioURL)
            }
            pendingSilentSave = nil
            extractedAudioURL = nil
            silentLevel = nil
            silentCoversWholeFile = false
            onUserClosed?()
            dismiss()
        case .useAnyway:
            guard let pending = pendingSilentSave else { return }
            pendingSilentSave = nil
            silentLevel = nil
            silentCoversWholeFile = false
            Task {
                await completeSave(
                    result: pending.result,
                    cafName: pending.cafName,
                    thumbnailFileName: pending.thumbnailFileName,
                    audioURL: pending.audioURL,
                    videoURL: videoURL ?? pending.audioURL
                )
            }
        case .fixedExisting:
            break
        }
    }

    private func deletePendingFile() {
        guard let pending = pendingSilentSave else { return }
        try? AudioConverter.shared.deleteSound(fileName: pending.cafName)
    }

    /// 変換後のサイズ見積り。動画は600秒上限だが選択範囲に応じて表示する（#79-8）
    @ViewBuilder
    private var sizeEstimateRow: some View {
        let selectionSeconds = endTime - startTime
        if AudioSizeEstimate.shouldShowWarning(seconds: selectionSeconds) {
            let size = AudioSizeEstimate.formattedSize(
                bytes: AudioSizeEstimate.estimatedFileSize(seconds: selectionSeconds)
            )
            Text(String(format: String(localized: "size_warning"), size))
                .font(.footnote)
                .foregroundStyle(Color.actionText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }
    /// 名前入力と保存ボタン。無音の知らせが出ているあいだは隠す（#256）。
    @ViewBuilder
    private func nameAndSaveControls(url: URL) -> some View {
        if let errorMessage {
            Text(errorMessage)
                .foregroundStyle(.red)
                .font(.caption)
        }

        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundStyle(Brand.orange)
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
            previewer.stop()
            extractAndConvert(from: url)
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
    }
}

// MARK: - TrimPreviewer

/// 選択範囲のプレビュー再生を管理する（#303 でくり返し再生に対応）。
///
/// - ▶ は選択範囲 `[開始, 終了]` をくり返し鳴らす。止めるのは ■・画面を閉じる・保存のときだけ
/// - 鳴っている間に範囲を変えても止めない。終了が再生位置より手前に来たら、すぐ開始へ戻る
/// - AVPlayer は使い回し、くり返しはシークで戻す（作り直すとつなぎ目で音が途切れる）
/// - 止めたあとも再生位置を残し、▶ はそこから鳴らす（範囲の外なら開始から）
@Observable
@MainActor
final class TrimPreviewer {
    private var player: AVPlayer?
    private var playerURL: URL?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    /// くり返す範囲（秒）。範囲を変えるたびに updateRange で置き換える
    private var loopStart: Double = 0
    private var loopEnd: Double = 0
    /// 頭へ戻すシークの途中で、古い再生位置により二重に戻さないための印
    private var isLooping = false

    private(set) var isPlaying = false

    /// 再生位置。止めたあとも最後の位置を残す（▶ はここから・#303）
    private(set) var currentTime: Double = 0

    // MARK: - 再生

    /// `range` を `from` からくり返し鳴らす。
    /// 鳴っている途中で呼ばれたら、その位置へ移ってそのまま続ける（止めない）。
    func play(url: URL, range: TrimRange, from: Double) {
        guard range.isValid, range.width > 0 else { return }
        activateAudioSession()

        let player = player(for: url)
        loopStart = range.start
        loopEnd = range.end
        isLooping = false

        // 終了ちょうどからは鳴らさず、開始から（#303）
        let start = from < range.end ? min(max(from, range.start), range.end) : range.start
        isPlaying = true
        currentTime = start
        player.pause()
        player.seek(to: Self.time(start), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.player?.play()
            }
        }
    }

    /// ■。再生位置は止めた位置のまま残す（#303）。
    func stop() {
        player?.pause()
        isPlaying = false
        isLooping = false
    }

    /// 次に ▶ で鳴らす位置。範囲の外なら開始から（#303）。
    func resumeTime(in range: TrimRange) -> Double {
        guard range.isValid else { return 0 }
        let isInside = currentTime >= range.start && currentTime < range.end
        return isInside ? currentTime : range.start
    }

    /// 選択範囲の変更を反映する（#303）。
    ///
    /// - 止めているとき: 開始が動いたら再生位置を新しい開始へ戻す。
    ///   開始が同じで範囲の外に出ただけなら、開始へ寄せる
    /// - 鳴っているとき: 終了が再生位置より手前に来たら、すぐ開始へ戻す
    func updateRange(_ range: TrimRange) {
        guard range.isValid, range.width > 0 else { return }
        let previousStart = loopStart
        loopStart = range.start
        loopEnd = range.end

        guard isPlaying else {
            if range.start != previousStart
                || currentTime < range.start
                || currentTime >= range.end {
                currentTime = range.start
            }
            return
        }
        guard let player else { return }
        if currentTime >= loopEnd - 0.001 || currentTime < loopStart {
            seekToLoopStart(player)
        }
    }

    // MARK: - Private

    /// URL が同じ間は同じ AVPlayer を使い回す（#303）。
    private func player(for url: URL) -> AVPlayer {
        if let player, playerURL == url { return player }
        teardownPlayer()

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)

        // 再生位置を 0.05 秒ごとに受け取り、終わりを越えたら頭へ戻す。
        // 終わりは毎回ここで判定するので、範囲が変わってもオブザーバーを付け直さなくてよい
        // （ファイル末尾＝終了のときも確実に戻る）。
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.handleTime(CMTimeGetSeconds(time))
            }
        }
        // 末尾で止まったときの保険（境界の取りこぼし対策）
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.seekToLoopStart(player)
            }
        }

        player = newPlayer
        playerURL = url
        return newPlayer
    }

    private func handleTime(_ time: Double) {
        guard isPlaying, !isLooping, time.isFinite else { return }
        if time >= loopEnd - 0.001 {
            if let player { seekToLoopStart(player) }
            return
        }
        currentTime = max(0, time)
    }

    private func seekToLoopStart(_ player: AVPlayer) {
        guard isPlaying, !isLooping else { return }
        isLooping = true
        currentTime = loopStart
        player.seek(to: Self.time(loopStart), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isLooping = false
                guard self.isPlaying else { return }
                self.player?.play()
            }
        }
    }

    private func activateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // 音が出せなくても、再生位置の表示は続ける
        }
    }

    private static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private func teardownPlayer() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player?.pause()
        player = nil
        playerURL = nil
    }
}

// MARK: - VideoTransferable

struct VideoTransferable: Transferable {
    let url: URL
    /// 元ファイル名（拡張子なし）。temp コピーで UUID 名になるのを防ぐため保持。
    let displayName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: tempURL)
            // 元ファイル名を保持（IMG_1234 等）。UUID なら空になる。
            let originalName = VideoFileImporter.defaultSoundName(from: received.file)
            return Self(url: tempURL, displayName: originalName)
        }
    }
}
