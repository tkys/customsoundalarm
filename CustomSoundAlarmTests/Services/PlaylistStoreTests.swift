import Foundation
import Testing
@testable import CustomSoundAlarm

@MainActor
struct PlaylistStoreTests {

    @Test
    func addUpdateAndRemove() {
        let store = PlaylistStore.shared
        let playlist = store.add(
            name: "test-\(UUID().uuidString)",
            tracks: [PlaylistTrack(soundFileName: "PresetMarimba.caf")]
        )
        defer { store.remove(id: playlist.id) }

        #expect(store.playlist(id: playlist.id) != nil)
        #expect(store.playlist(id: playlist.id)?.tracks.count == 1)

        var updated = playlist
        updated.name = "renamed"
        store.update(updated)
        #expect(store.playlist(id: playlist.id)?.name == "renamed")

        store.remove(id: playlist.id)
        #expect(store.playlist(id: playlist.id) == nil)
    }

    @Test
    func trackDisplayNameUsesSoundStore() {
        let store = PlaylistStore.shared
        let name = store.trackDisplayName(for: "PresetMarimba.caf")
        #expect(!name.isEmpty)
        #expect(name != "PresetMarimba.caf")
    }

    @Test
    func removeTrack_dropsOnlyTheDeletedSoundAndNotifiesAffectedPlaylists() {
        let store = PlaylistStore.shared
        let removedFileName = "uitest-remove-\(UUID().uuidString).caf"
        let otherFileName = "uitest-keep-\(UUID().uuidString).caf"
        let affected = store.add(
            name: "affected-\(UUID().uuidString)",
            tracks: [
                PlaylistTrack(soundFileName: removedFileName),
                PlaylistTrack(soundFileName: "PresetMarimba.caf")
            ]
        )
        let unaffected = store.add(
            name: "unaffected-\(UUID().uuidString)",
            tracks: [PlaylistTrack(soundFileName: otherFileName)]
        )
        defer {
            store.remove(id: affected.id)
            store.remove(id: unaffected.id)
        }

        var notified: [UUID] = []
        let previous = store.onPlaylistChanged
        store.onPlaylistChanged = { notified.append($0) }
        defer { store.onPlaylistChanged = previous }

        let result = store.removeTrack(fileName: removedFileName)

        #expect(result == [affected.id])
        #expect(
            store.playlist(id: affected.id)?.tracks.map(\.soundFileName)
                == ["PresetMarimba.caf"]
        )
        #expect(store.playlist(id: unaffected.id)?.tracks.count == 1)
        #expect(notified == [affected.id])
    }

    @Test
    func update_notifiesChangedPlaylist() {
        let store = PlaylistStore.shared
        var playlist = store.add(name: "notify-\(UUID().uuidString)")
        defer { store.remove(id: playlist.id) }

        var notified: [UUID] = []
        let previous = store.onPlaylistChanged
        store.onPlaylistChanged = { notified.append($0) }
        defer { store.onPlaylistChanged = previous }

        playlist.playOrder = .shuffle
        store.update(playlist)

        #expect(notified == [playlist.id])
    }
}
