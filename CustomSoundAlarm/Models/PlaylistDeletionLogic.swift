import Foundation

/// プレイリスト削除時に、使っていたアラームを1つの音へ切り替える純ロジック（#160）。
enum PlaylistDeletionLogic {
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
        for alarm in updated where alarm.playlistID == nil {
            store.update(alarm)
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
