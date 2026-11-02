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

    /// 計測は PR-B で接続する（PR-A では no-op）。
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
    /// - Parameter forceNewOrder: 停止時にシャッフル/ランダムを作り直すときに true
    func prepareSound(
        for input: PlaylistRenderInput,
        forceNewOrder: Bool = false
    ) async -> PlaylistSoundResolution {
        guard input.usesPlaylistFeatures else {
            return PlaylistSoundResolution(
                fileName: input.fallbackFileName,
                usedFallback: false,
                isProcessed: false
            )
        }

        let playlist = PlaylistStore.shared.playlist(id: input.playlistID)
        if input.soundMode.isPlaylist, playlist == nil {
            return fallback(for: input, reason: .missingPlaylist)
        }

        let tracks = sourceTracks(for: input, playlist: playlist)
        guard !tracks.isEmpty else {
            return fallback(for: input, reason: .noTracks)
        }

        let seed = orderSeed(for: input, forceNewOrder: forceNewOrder)
        let ordered = PlaylistRenderLogic.orderedTracks(
            tracks,
            mode: input.soundMode.isPlaylist ? input.soundMode : .playlistOrder,
            seed: seed
        )
        let resolved = ordered.compactMap { track -> (PlaylistTrack, URL)? in
            guard let url = sourceURL(for: track.soundFileName) else { return nil }
            return (track, url)
        }
        guard !resolved.isEmpty else {
            return fallback(for: input, reason: .noTracks)
        }

        let signature = signature(
            input: input,
            ordered: resolved.map(\.0)
        )
        let key = "primary:\(input.entryID.uuidString)"
        if let cached = cache[key],
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
            fade: input.fadeSettings,
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
            return fallback(for: input, reason: PlaylistRenderFailureReason(error))
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            return fallback(for: input, reason: .renderFailed)
        }
    }

    /// 最終アラーム用の音を用意する。プレイリストでなければ nil
    /// （呼び出し側は従来の「大きくした版」を使う）。
    /// バックアップには「やさしく鳴り始める」を適用しない。
    func prepareBackupSound(
        for input: PlaylistRenderInput,
        forceNewOrder: Bool = false
    ) async -> PlaylistSoundResolution? {
        guard input.soundMode.isPlaylist else { return nil }

        let playlist = PlaylistStore.shared.playlist(id: input.playlistID)
        guard let playlist else {
            return fallback(for: input, reason: .missingPlaylist)
        }

        let tracks = sourceTracks(for: input, playlist: playlist)
        guard !tracks.isEmpty else {
            return fallback(for: input, reason: .noTracks)
        }

        let seed = orderSeed(for: input, forceNewOrder: forceNewOrder)
        let ordered = PlaylistRenderLogic.orderedTracks(
            tracks,
            mode: input.soundMode,
            seed: seed
        )
        let resolved = ordered.compactMap { track -> (PlaylistTrack, URL)? in
            guard let url = sourceURL(for: track.soundFileName) else { return nil }
            return (track, url)
        }
        guard !resolved.isEmpty else {
            return fallback(for: input, reason: .noTracks)
        }

        var backupFade = input.fadeSettings
        backupFade.fadeIn = .off
        let signature = signature(
            input: input,
            ordered: resolved.map(\.0),
            backup: true
        )
        let key = "backup:\(input.entryID.uuidString)"
        if let cached = cache[key],
           cached.signature == signature,
           fileExists(cached.fileName) {
            return PlaylistSoundResolution(
                fileName: cached.fileName,
                usedFallback: false,
                isProcessed: true
            )
        }

        let slot = nextSlot(after: cache[key]?.slot)
        let outputFileName = "\(input.entryID.uuidString).playlist.backup.\(slot).caf"
        let outputURL = soundsDirectory.appendingPathComponent(outputFileName)
        let tempURL = soundsDirectory.appendingPathComponent(
            "\(input.entryID.uuidString).playlist.backup.\(slot).\(UUID().uuidString).tmp.caf"
        )
        let request = PlaylistRenderRequest(
            trackURLs: resolved.map(\.1),
            fade: backupFade,
            applyFadeIn: false,
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
            return fallback(for: input, reason: PlaylistRenderFailureReason(error))
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            return fallback(for: input, reason: .renderFailed)
        }
    }

    /// 使われなくなったスロット／削除されたアラームのファイルを削除する。
    /// 現在のキャッシュが指すファイルは残す（次の同期で使う）。
    func cleanupUnusedFiles(inputs: [PlaylistRenderInput]) {
        let byID = Dictionary(uniqueKeysWithValues: inputs.map { ($0.entryID, $0) })
        let validIDs = Set(inputs.filter(\.usesPlaylistFeatures).map(\.entryID.uuidString))
        let activeFileNames = Set(cache.compactMap { key, entry -> String? in
            let idPart = key
                .replacingOccurrences(of: "primary:", with: "")
                .replacingOccurrences(of: "backup:", with: "")
            return validIDs.contains(idPart) ? entry.fileName : nil
        })
        let files = (try? FileManager.default.contentsOfDirectory(
            at: soundsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []

        for file in files {
            let name = file.lastPathComponent
            guard name.hasSuffix(".caf"), name.contains(".playlist.") else { continue }
            if activeFileNames.contains(name) { continue }

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
            let idPart = key
                .replacingOccurrences(of: "primary:", with: "")
                .replacingOccurrences(of: "backup:", with: "")
            return validIDs.contains(idPart)
        }
        saveCache()
    }

    // MARK: - Helpers

    private func sourceTracks(
        for input: PlaylistRenderInput,
        playlist: Playlist?
    ) -> [PlaylistTrack] {
        if input.soundMode.isPlaylist {
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

    private func orderSeed(
        for input: PlaylistRenderInput,
        forceNewOrder: Bool
    ) -> UInt64 {
        if forceNewOrder, input.soundMode.changesOrderOnStop {
            sessionToken = UUID()
        }
        // 同じセッション・同じアラームでは同じ順序になる。
        let text = "\(sessionToken.uuidString)|\(input.entryID.uuidString)"
        return UInt64(truncatingIfNeeded: text.hashValue)
    }

    private func signature(
        input: PlaylistRenderInput,
        ordered: [PlaylistTrack],
        backup: Bool = false
    ) -> String {
        let fade = input.fadeSettings
        let order = ordered.map(\.soundFileName).joined(separator: ",")
        let mode = input.soundMode.rawValue
        let fadeIn = backup ? "off" : fade.fadeIn.analyticsValue
        let gap = fade.gapFade.analyticsValue
        let end = fade.endFade ? "1" : "0"
        let token = input.soundMode.changesOrderOnStop ? sessionToken.uuidString : "fixed"
        return [
            "v\(Self.renderVersion)",
            mode,
            order,
            fadeIn,
            gap,
            end,
            token,
            backup ? "backup" : "primary"
        ].joined(separator: "|")
    }

    private func fallback(
        for input: PlaylistRenderInput,
        reason: PlaylistRenderFailureReason
    ) -> PlaylistSoundResolution {
        let playlist = PlaylistStore.shared.playlist(id: input.playlistID)
        let firstTrack = playlist?.tracks.first?.soundFileName
        let fileName = firstTrack ?? input.fallbackFileName
        onRenderFailed?(reason)
        onFallback?()
        return PlaylistSoundResolution(
            fileName: fileName,
            usedFallback: true,
            isProcessed: false
        )
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
