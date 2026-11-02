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
}
