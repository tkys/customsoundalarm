import Testing
import Foundation
@testable import CustomSoundAlarm

struct AnalyticsUserPropertiesTests {

    @Test
    func backupAlarmCount_countsEntriesWithBackupOn() {
        let alarms = [
            AlarmEntry(backupMinutes: 15),
            AlarmEntry(backupMinutes: 30),
            AlarmEntry(backupMinutes: nil)
        ]
        #expect(AnalyticsUserProperties.backupAlarmCount(alarms: alarms) == 2)
        #expect(AnalyticsUserProperties.backupAlarmCount(alarms: []) == 0)
    }

    @Test
    func firstInstallBuild_parsesBuildNumber() {
        #expect(AnalyticsUserProperties.firstInstallBuild(fromOriginalAppVersion: "6") == 6)
        #expect(AnalyticsUserProperties.firstInstallBuild(fromOriginalAppVersion: " 12 ") == 12)
    }

    @Test
    func firstInstallBuild_nilForUnavailableOrInvalid() {
        #expect(AnalyticsUserProperties.firstInstallBuild(fromOriginalAppVersion: nil) == nil)
        #expect(AnalyticsUserProperties.firstInstallBuild(fromOriginalAppVersion: "") == nil)
        #expect(AnalyticsUserProperties.firstInstallBuild(fromOriginalAppVersion: "1.0") == nil)
        #expect(AnalyticsUserProperties.firstInstallBuild(fromOriginalAppVersion: "abc") == nil)
        #expect(AnalyticsUserProperties.firstInstallBuild(fromOriginalAppVersion: "-1") == nil)
    }

    @Test
    func soundKindProperties_areBooleans() {
        let sounds = [
            AlarmSound(name: "Song", fileName: "a.caf", contentKind: .singing),
            AlarmSound(name: "Voice", fileName: "b.caf", contentKind: .voice),
            AlarmSound(name: "Cat", fileName: "c.caf", contentKind: .cat),
            AlarmSound(name: "Unknown", fileName: "d.caf", contentKind: .unknown),
            AlarmSound(name: "Preset", fileName: "p.caf", isPreset: true, contentKind: .instrumental)
        ]
        let props = AnalyticsUserProperties.soundKindProperties(sounds: sounds)

        #expect(props["has_music_sound"] as? Bool == true)
        #expect(props["has_voice_sound"] as? Bool == true)
        #expect(props["has_animal_sound"] as? Bool == true)
    }

    @Test
    func soundKindProperties_ignorePresetsAndUnknown() {
        let sounds = [
            AlarmSound(name: "Unknown", fileName: "d.caf", contentKind: .unknown),
            AlarmSound(name: "Preset", fileName: "p.caf", isPreset: true, contentKind: .instrumental),
            AlarmSound(name: "Nature", fileName: "n.caf", contentKind: .nature)
        ]
        let props = AnalyticsUserProperties.soundKindProperties(sounds: sounds)

        #expect(props["has_music_sound"] as? Bool == false)
        #expect(props["has_voice_sound"] as? Bool == false)
        #expect(props["has_animal_sound"] as? Bool == false)
    }
}
