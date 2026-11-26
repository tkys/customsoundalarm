import Foundation
import Testing
@testable import CustomSoundAlarm

struct FadeInAvailabilityTests {

    @Test
    func defaultSoundWithoutPlaylistIsUnavailable() {
        #expect(!FadeInAvailability.isAvailable(soundFileName: "", playlistID: nil))
    }

    @Test
    func presetSoundIsAvailable() {
        #expect(FadeInAvailability.isAvailable(
            soundFileName: "PresetMarimba.caf",
            playlistID: nil
        ))
    }

    @Test
    func importedSoundIsAvailable() {
        #expect(FadeInAvailability.isAvailable(
            soundFileName: "Imported.caf",
            playlistID: nil
        ))
    }

    @Test
    func playlistIsAvailableWithoutFallbackSound() {
        #expect(FadeInAvailability.isAvailable(
            soundFileName: "",
            playlistID: UUID()
        ))
    }

    @Test
    func playlistWithFallbackSoundIsAvailable() {
        #expect(FadeInAvailability.isAvailable(
            soundFileName: "PresetMarimba.caf",
            playlistID: UUID()
        ))
    }
}
