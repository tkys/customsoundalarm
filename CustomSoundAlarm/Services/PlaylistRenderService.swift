import Foundation

/// プレイリスト書き出しの失敗理由（計測用・#151）。
enum PlaylistRenderFailureReason: String, Sendable, Equatable {
    case noTracks = "no_tracks"
    case tooLong = "too_long"
    case renderFailed = "render_failed"
    case writeFailed = "write_failed"
    case missingPlaylist = "missing_playlist"

    init(_ error: PlaylistRenderError) {
        switch error {
        case .noTracks: self = .noTracks
        case .unreadableSource: self = .noTracks
        case .renderFailed: self = .renderFailed
        case .writeFailed: self = .writeFailed
        case .tooLong: self = .tooLong
        }
    }
}

/// 書き出し結果。`fileName` を AlarmKit の `.named()` に渡す。
struct PlaylistSoundResolution: Equatable, Sendable {
    let fileName: String
    let usedFallback: Bool
    let isProcessed: Bool
}

/// プレイリストの書き出しキャッシュ（#151）。
private struct PlaylistRenderCacheEntry: Codable, Equatable {
    let signature: String
    let fileName: String
    let slot: String
    let order: [String]
    /// 曲 ID の順番（#169 シャッフルで前回と同じ並びを避ける）
    let orderTrackIDs: [UUID]?
    /// シャッフル/1曲ランダムの順番を決めた値（アラームごと）
    let orderSeed: UInt64?
    /// この順番を作ったアプリ起動セッション
    let sessionToken: UUID?
    let renderVersion: Int
    let generatedAt: Date
}

/// プレイリストの書き出し・キャッシュ・フォールバック（#151）。
///
/// シャッフル／1曲ランダムは、同じファイル名の上書きが次回の鳴りに
/// 反映されるか未検証のため、`<id>.playlist.a.caf` / `.b.caf` を交互に使う。
/// 書き出しは一時ファイル → 新しいスロットへアトミックに置き換え、
/// 失敗時は既存ファイルを残してフォールバックする。
@MainActor
final class PlaylistRenderService {
    static let shared = PlaylistRenderService()

    /// 生成方式の版。古いファイルは作り直す。
    private static let renderVersion = 1
    private static let tempLifetime: TimeInterval = 10 * 60

    /// 書き出し失敗・フォールバックの計測フック。
    var onRenderFailed: ((PlaylistRenderFailureReason) -> Void)?
    var onFallback: (() -> Void)?

    private var cache: [String: PlaylistRenderCacheEntry] = [:]

    /// アプリ起動時に更新する。シャッフル/ランダムの次回順を変える。
    private var sessionToken = UUID()

    private var soundsDirectory: URL {
        AudioConverter.shared.soundsDirectory
    }

    private init() {
        loadCache()
    }

    /// アプリ起動時に呼ぶ。次回のシャッフル/ランダムを新しい順にする。
    func beginNewSession() {
        sessionToken = UUID()
    }

    /// 通常アラーム用の音を用意する。
    /// - Parameters:
    ///   - forceNewOrder: 停止時にシャッフル/ランダムを作り直すときに true
    ///   - reportEvents: false のときは署名計算用で、失敗・フォールバックを計測しない
    func prepareSound(
        for input: PlaylistRenderInput,
        forceNewOrder: Bool = false,
        reportEvents: Bool = true
    ) async -> PlaylistSoundResolution {
        guard input.usesPlaylistFeatures else {
            return PlaylistSoundResolution(
                fileName: input.fallbackFileName,
                usedFallback: false,
                isProcessed: false
            )
        }

        let playlist = PlaylistStore.shared.playlist(id: input.playlistID)
        if input.isPlaylist, playlist == nil {
            return fallback(for: input, reason: .missingPlaylist, reportEvents: reportEvents)
        }

        let tracks = sourceTracks(for: input, playlist: playlist)
        guard !tracks.isEmpty else {
            return fallback(for: input, reason: .noTracks, reportEvents: reportEvents)
        }

        let key = "primary:\(input.entryID.uuidString)"
        let cached = cache[key]
        // 起動セッションが変わったとき、または停止後の作り直しだけ順番を変える。
        let needsNewOrder = forceNewOrder
            || ((playlist?.playOrder.changesOrderOnStop ?? false)
                && cached?.sessionToken != sessionToken)
        let seed = needsNewOrder
            ? Self.newOrderSeed()
            : (cached?.orderSeed ?? Self.newOrderSeed())
        let playOrder = playlist?.playOrder ?? .inOrder
        let baseOrdered = PlaylistRenderLogic.orderedTracks(
            tracks,
            order: playOrder,
            seed: seed
        )

        let ordered: [PlaylistTrack]
        if needsNewOrder {
            // 新しい順番を作るときだけ、前回と同じ並びを避ける（#169）。
            if playOrder == .shuffle,
               let previousOrder = previousOrderTrackIDs(cached: cached, tracks: tracks),
               !previousOrder.isEmpty {
                ordered = PlaylistRenderLogic.orderedTracks(
                    tracks,
                    order: playOrder,
                    seed: seed,
                    avoidingPreviousOrder: previousOrder
                )
            } else {
                ordered = baseOrdered
            }
        } else if playOrder == .shuffle,
                  let cachedOrder = cached?.orderTrackIDs,
                  !cachedOrder.isEmpty {
            // キャッシュ済みのシャッフル順をそのまま再現する。
            // 追加された曲は末尾に足す。
            ordered = tracksInOrder(tracks, trackIDs: cachedOrder)
        } else {
            ordered = baseOrdered
        }

        let resolved = ordered.compactMap { track -> (PlaylistTrack, URL)? in
            guard let url = sourceURL(for: track.soundFileName) else { return nil }
            return (track, url)
        }
        guard !resolved.isEmpty else {
            return fallback(for: input, reason: .noTracks, reportEvents: reportEvents)
        }

        let signature = signature(
            input: input,
            ordered: resolved.map(\.0)
        )
        if !needsNewOrder,
           let cached,
           cached.signature == signature,
           fileExists(cached.fileName) {
            return PlaylistSoundResolution(
                fileName: cached.fileName,
                usedFallback: false,
                isProcessed: true
            )
        }

        let slot = nextSlot(after: cache[key]?.slot)
        let outputFileName = "\(input.entryID.uuidString).playlist.\(slot).caf"
        let outputURL = soundsDirectory.appendingPathComponent(outputFileName)
        let tempURL = soundsDirectory.appendingPathComponent(
            "\(input.entryID.uuidString).playlist.\(slot).\(UUID().uuidString).tmp.caf"
        )
        let request = PlaylistRenderRequest(
            trackURLs: resolved.map(\.1),
            fadeIn: input.fadeIn,
            transition: playlist?.transition ?? .off,
            applyFadeIn: true,
            outputURL: tempURL
        )

        do {
            _ = try await Task.detached(priority: .utility) {
                try PlaylistRenderer.generate(request)
            }.value
            try atomicInstall(tempURL, at: outputURL)
            cache[key] = PlaylistRenderCacheEntry(
                signature: signature,
                fileName: outputFileName,
                slot: slot,
                order: resolved.map(\.0.soundFileName),
                orderTrackIDs: resolved.map(\.0.id),
                orderSeed: seed,
                sessionToken: sessionToken,
                renderVersion: Self.renderVersion,
                generatedAt: Date()
            )
            saveCache()
            return PlaylistSoundResolution(
                fileName: outputFileName,
                usedFallback: false,
                isProcessed: true
            )
        } catch let error as PlaylistRenderError {
            try? FileManager.default.removeItem(at: tempURL)
            return fallback(for: input, reason: PlaylistRenderFailureReason(error), reportEvents: reportEvents)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            return fallback(for: input, reason: .renderFailed, reportEvents: reportEvents)
        }
    }

    /// 書き出し済みのファイル名を返す（描画しない・#163）。
    /// バックグラウンド起動時の署名計算で、新しい順番の書き出しを避けるために使う。
    func cachedSoundFileName(for input: PlaylistRenderInput) -> String? {
        guard input.usesPlaylistFeatures else {
            return input.fallbackFileName
        }
        let key = "primary:\(input.entryID.uuidString)"
        guard let cached = cache[key], fileExists(cached.fileName) else {
            return nil
        }
        return cached.fileName
    }

    /// 使われなくなったスロット／削除されたアラームのファイルを削除する。
    /// - Parameters:
    ///   - inputs: 現在プレイリスト機能を使っているアラーム
    ///   - registeredFileNames: 現在 AlarmKit に登録している音ファイル名。
    ///     登録中のファイルは、キャッシュが切り替わっていても消さない。
    func cleanupUnusedFiles(
        inputs: [PlaylistRenderInput],
        keeping registeredFileNames: Set<String> = []
    ) {
        let byID = Dictionary(uniqueKeysWithValues: inputs.map { ($0.entryID, $0) })
        let validIDs = Set(inputs.filter(\.usesPlaylistFeatures).map(\.entryID.uuidString))
        let activeFileNames = Set(cache.compactMap { key, entry -> String? in
            guard key.hasPrefix("primary:") else { return nil }
            let idPart = key.replacingOccurrences(of: "primary:", with: "")
            return validIDs.contains(idPart) ? entry.fileName : nil
        })
        let files = (try? FileManager.default.contentsOfDirectory(
            at: soundsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []

        for file in files {
            let name = file.lastPathComponent

            // 書き出し中の一時ファイルは、一定時間より古いものだけ消す。
            if name.hasSuffix(".tmp.caf") {
                let modified = try? file.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                if let modified, Date().timeIntervalSince(modified) > Self.tempLifetime {
                    try? FileManager.default.removeItem(at: file)
                }
                continue
            }

            if name == Self.testRingSoundFileName { continue }
            if name == Self.previewSoundFileName { continue }
            guard name.hasSuffix(".caf"), name.contains(".playlist.") else { continue }

            // 旧方式のプレイリスト・バックアップは、登録中でなければ削除する（#151）
            if name.contains(".playlist.backup.") {
                if !registeredFileNames.contains(name) {
                    try? FileManager.default.removeItem(at: file)
                }
                continue
            }

            if activeFileNames.contains(name) || registeredFileNames.contains(name) {
                continue
            }

            let idPart = name.components(separatedBy: ".playlist.").first ?? ""
            guard let entryID = UUID(uuidString: idPart),
                  let input = byID[entryID],
                  input.usesPlaylistFeatures else {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            // 使わなくなった側（a/b）の掃除
            try? FileManager.default.removeItem(at: file)
        }

        cache = cache.filter { key, _ in
            guard key.hasPrefix("primary:") else { return false }
            let idPart = key.replacingOccurrences(of: "primary:", with: "")
            return validIDs.contains(idPart)
        }
        saveCache()
    }

    // MARK: - Helpers

    private func sourceTracks(
        for input: PlaylistRenderInput,
        playlist: Playlist?
    ) -> [PlaylistTrack] {
        if input.isPlaylist {
            return playlist?.tracks ?? []
        }
        return [PlaylistTrack(soundFileName: input.fallbackFileName)]
    }

    private func sourceURL(for fileName: String) -> URL? {
        guard !fileName.isEmpty else { return nil }
        let base = fileName.replacingOccurrences(of: ".caf", with: "")
        if let bundleURL = Bundle.main.url(forResource: base, withExtension: "caf") {
            return bundleURL
        }
        let url = soundsDirectory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Test ring (#169)

    /// 試し鳴らし専用の書き出しファイル名。停止・60秒経過・次回起動で削除する。
    static let testRingSoundFileName = "test.playlist.caf"

    /// 試し鳴らしのシャッフルで前回と同じ並びを避けるための曲 ID 順。
    private var lastTestRingOrderTrackIDs: [UUID] = []

    /// 編集中の内容で試し鳴らし用の音を書き出す（#169）。
    /// 通常のアラーム用キャッシュには触れず、`test.playlist.caf` だけを更新する。
    func prepareTestRingSound(
        for input: PlaylistRenderInput
    ) async -> PlaylistSoundResolution {
        guard input.usesPlaylistFeatures else {
            return PlaylistSoundResolution(
                fileName: input.fallbackFileName,
                usedFallback: false,
                isProcessed: false
            )
        }

        let playlist = PlaylistStore.shared.playlist(id: input.playlistID)
        if input.isPlaylist, playlist == nil {
            return fallback(for: input, reason: .missingPlaylist)
        }

        let tracks = sourceTracks(for: input, playlist: playlist)
        guard !tracks.isEmpty else {
            return fallback(for: input, reason: .noTracks)
        }

        let playOrder = playlist?.playOrder ?? .inOrder
        let ordered = PlaylistRenderLogic.orderedTracks(
            tracks,
            order: playOrder,
            seed: Self.newOrderSeed(),
            avoidingPreviousOrder: playOrder == .shuffle
                ? lastTestRingOrderTrackIDs
                : []
        )
        let resolved = ordered.compactMap { track -> (PlaylistTrack, URL)? in
            guard let url = sourceURL(for: track.soundFileName) else { return nil }
            return (track, url)
        }
        guard !resolved.isEmpty else {
            return fallback(for: input, reason: .noTracks)
        }

        let outputURL = soundsDirectory.appendingPathComponent(
            Self.testRingSoundFileName
        )
        let tempURL = soundsDirectory.appendingPathComponent(
            "\(Self.testRingSoundFileName).\(UUID().uuidString).tmp.caf"
        )
        let request = PlaylistRenderRequest(
            trackURLs: resolved.map(\.1),
            fadeIn: input.fadeIn,
            transition: playlist?.transition ?? .off,
            applyFadeIn: true,
            outputURL: tempURL
        )

        do {
            _ = try await Task.detached(priority: .userInitiated) {
                try PlaylistRenderer.generate(request)
            }.value
            try atomicInstall(tempURL, at: outputURL)
            lastTestRingOrderTrackIDs = resolved.map(\.0.id)
            return PlaylistSoundResolution(
                fileName: Self.testRingSoundFileName,
                usedFallback: false,
                isProcessed: true
            )
        } catch let error as PlaylistRenderError {
            try? FileManager.default.removeItem(at: tempURL)
            return fallback(for: input, reason: PlaylistRenderFailureReason(error))
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            return fallback(for: input, reason: .renderFailed)
        }
    }

    /// 試し鳴らし用ファイルを削除する（停止・タイムアウト・起動時）。
    func deleteTestRingSound() {
        let url = soundsDirectory.appendingPathComponent(
            Self.testRingSoundFileName
        )
        try? FileManager.default.removeItem(at: url)
        lastTestRingOrderTrackIDs = []
    }

    // MARK: - Playlist preview (#169)

    /// プレイリスト試聴用の書き出しファイル名。画面を離れたら削除する。
    static let previewSoundFileName = "playlist.preview.caf"

    /// 試聴のシャッフルで前回と同じ並びを避けるための曲 ID 順。
    private var lastPreviewOrderTrackIDs: [UUID] = []

    /// 編集中の曲・再生順・つなぎ方でプレビュー用の音を書き出す（#169）。
    func preparePreviewSound(
        tracks: [PlaylistTrack],
        playOrder: PlaylistPlayOrder,
        transition: PlaylistTransition
    ) async -> PlaylistSoundResolution {
        guard !tracks.isEmpty else {
            return previewFallback(tracks: tracks)
        }

        let ordered = PlaylistRenderLogic.orderedTracks(
            tracks,
            order: playOrder,
            seed: Self.newOrderSeed(),
            avoidingPreviousOrder: playOrder == .shuffle
                ? lastPreviewOrderTrackIDs
                : []
        )
        let resolved = ordered.compactMap { track -> (PlaylistTrack, URL)? in
            guard let url = sourceURL(for: track.soundFileName) else { return nil }
            return (track, url)
        }
        guard !resolved.isEmpty else {
            return previewFallback(tracks: tracks)
        }

        let outputURL = soundsDirectory.appendingPathComponent(
            Self.previewSoundFileName
        )
        let tempURL = soundsDirectory.appendingPathComponent(
            "\(Self.previewSoundFileName).\(UUID().uuidString).tmp.caf"
        )
        let request = PlaylistRenderRequest(
            trackURLs: resolved.map(\.1),
            fadeIn: .off,
            transition: transition,
            applyFadeIn: false,
            outputURL: tempURL
        )

        do {
            _ = try await Task.detached(priority: .userInitiated) {
                try PlaylistRenderer.generate(request)
            }.value
            try atomicInstall(tempURL, at: outputURL)
            lastPreviewOrderTrackIDs = resolved.map(\.0.id)
            return PlaylistSoundResolution(
                fileName: Self.previewSoundFileName,
                usedFallback: false,
                isProcessed: true
            )
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            return previewFallback(tracks: tracks)
        }
    }

    /// プレビュー用ファイルを削除する（停止・画面を離れたとき）。
    func deletePreviewSound() {
        let url = soundsDirectory.appendingPathComponent(
            Self.previewSoundFileName
        )
        try? FileManager.default.removeItem(at: url)
        lastPreviewOrderTrackIDs = []
    }

    private func previewFallback(
        tracks: [PlaylistTrack]
    ) -> PlaylistSoundResolution {
        let fileName = PlaylistFallbackLogic.fileName(
            tracks: tracks,
            fallbackFileName: "",
            isAvailable: { sourceURL(for: $0) != nil },
            defaultFileName: defaultFallbackFileName
        )
        return PlaylistSoundResolution(
            fileName: fileName,
            usedFallback: true,
            isProcessed: false
        )
    }

    /// 旧キャッシュ（orderTrackIDs が無い）からも前回の曲 ID 順を復元する。
    private func previousOrderTrackIDs(
        cached: PlaylistRenderCacheEntry?,
        tracks: [PlaylistTrack]
    ) -> [UUID]? {
        if let ids = cached?.orderTrackIDs {
            return ids
        }
        guard let fileNames = cached?.order, !fileNames.isEmpty else {
            return nil
        }
        var remaining = tracks
        var ids: [UUID] = []
        for name in fileNames {
            guard let index = remaining.firstIndex(where: {
                $0.soundFileName == name
            }) else { continue }
            ids.append(remaining.remove(at: index).id)
        }
        return ids.isEmpty ? nil : ids
    }

    /// 保存済みの曲 ID 順で現在のトラックを並べ、追加された曲は末尾に足す。
    private func tracksInOrder(
        _ tracks: [PlaylistTrack],
        trackIDs: [UUID]
    ) -> [PlaylistTrack] {
        let byID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        var ordered = trackIDs.compactMap { byID[$0] }
        let included = Set(ordered.map(\.id))
        ordered.append(contentsOf: tracks.filter { !included.contains($0.id) })
        return ordered
    }

    private func signature(
        input: PlaylistRenderInput,
        ordered: [PlaylistTrack]
    ) -> String {
        let playlist = PlaylistStore.shared.playlist(id: input.playlistID)
        let order = ordered.map(\.soundFileName).joined(separator: ",")
        let playOrder = playlist?.playOrder.analyticsValue ?? PlaylistPlayOrder.inOrder.analyticsValue
        let transition = playlist?.transition.analyticsValue ?? PlaylistTransition.off.analyticsValue
        let fadeIn = input.fadeIn.analyticsValue
        return [
            "v\(Self.renderVersion)",
            playOrder,
            transition,
            order,
            fadeIn
        ].joined(separator: "|")
    }

    private func reportFailure(_ reason: PlaylistRenderFailureReason) {
        onRenderFailed?(reason)
        onFallback?()
    }

    private static func newOrderSeed() -> UInt64 {
        UInt64.random(in: 0...UInt64.max)
    }

    private func fallback(
        for input: PlaylistRenderInput,
        reason: PlaylistRenderFailureReason,
        reportEvents: Bool = true
    ) -> PlaylistSoundResolution {
        let playlist = PlaylistStore.shared.playlist(id: input.playlistID)
        let fileName = PlaylistFallbackLogic.fileName(
            tracks: playlist?.tracks ?? [],
            fallbackFileName: input.fallbackFileName,
            isAvailable: { sourceURL(for: $0) != nil },
            defaultFileName: defaultFallbackFileName
        )
        if reportEvents {
            onRenderFailed?(reason)
            onFallback?()
        }
        return PlaylistSoundResolution(
            fileName: fileName,
            usedFallback: true,
            isProcessed: false
        )
    }

    private var defaultFallbackFileName: String {
        SoundStore.presetDefinitions.first?.fileName ?? "PresetMarimba.caf"
    }

    private func nextSlot(after current: String?) -> String {
        current == "a" ? "b" : "a"
    }

    private func fileExists(_ fileName: String) -> Bool {
        !fileName.isEmpty
            && FileManager.default.fileExists(
                atPath: soundsDirectory.appendingPathComponent(fileName).path
            )
    }

    /// 一時ファイルを新しいスロットへ移す。既存スロットがあればアトミックに置き換える。
    /// 失敗時は既存ファイルを残す。
    private func atomicInstall(_ tempURL: URL, at destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: destination)
        }
    }

    // MARK: - Cache persistence

    private func loadCache() {
        guard let data = AppGroup.playlistRenderCacheData,
              let decoded = try? JSONDecoder().decode(
                [String: PlaylistRenderCacheEntry].self,
                from: data
              ) else {
            return
        }
        cache = decoded
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        AppGroup.playlistRenderCacheData = data
    }
}
