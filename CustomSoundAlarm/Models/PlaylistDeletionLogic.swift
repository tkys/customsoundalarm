import Foundation

/// プレイリスト削除時に、使っていたアラームを1つの音へ切り替える純ロジック（#160）。
enum PlaylistDeletionLogic {
    /// 削除の確認ダイアログに出す「使っているアラーム」の件数。
    static func affectedAlarmCount(
        playlistID: UUID,
        alarms: [AlarmEntry]
    ) -> Int {
        alarms.filter { $0.playlistID == playlistID }.count
    }

    static func updatedAlarms(
        playlistID: UUID,
        trackFileNames: [String],
        alarms: [AlarmEntry],
        isAvailable: (String) -> Bool,
        defaultFileName: String
    ) -> [AlarmEntry] {
        let fallback = trackFileNames.first(where: isAvailable) ?? defaultFileName
        return alarms.map { alarm in
            guard alarm.playlistID == playlistID else { return alarm }
            var updated = alarm
            updated.playlistID = nil
            updated.soundFileName = fallback
            return updated
        }
    }
}

/// プレイリスト削除の適用（#160）。確認 UI は PR-2 で追加する。
@MainActor
enum PlaylistDeletionService {
    static func delete(playlistID: UUID) {
        guard let playlist = PlaylistStore.shared.playlist(id: playlistID) else {
            return
        }
        let store = AlarmStore.shared
        let updated = PlaylistDeletionLogic.updatedAlarms(
            playlistID: playlistID,
            trackFileNames: playlist.tracks.map(\.soundFileName),
            alarms: store.alarms,
            isAvailable: isAvailable,
            defaultFileName: SoundStore.presetDefinitions.first?.fileName
                ?? "PresetMarimba.caf"
        )
        // 変わったアラームだけ保存する（無関係なアラームを触らない）
        for (old, new) in zip(store.alarms, updated) where old != new {
            store.update(new)
        }
        PlaylistStore.shared.remove(id: playlistID)
        AlarmScheduler.shared.syncAlarms(store.alarms)
    }

    private static func isAvailable(_ fileName: String) -> Bool {
        guard !fileName.isEmpty else { return false }
        let base = fileName.replacingOccurrences(of: ".caf", with: "")
        if Bundle.main.url(forResource: base, withExtension: "caf") != nil {
            return true
        }
        let url = AudioConverter.shared.soundsDirectory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path)
    }
}
