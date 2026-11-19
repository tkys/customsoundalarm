import Testing
import Foundation
@testable import CustomSoundAlarm

struct SilentSoundLogicTests {

    @Test
    func silentWhenPeakAfterGainIsBelowThreshold() {
        #expect(SilentSoundLogic.judge(
            lufsBefore: -10,
            peakDb: -70,
            gainDb: 0
        ) == .silent)
        #expect(SilentSoundLogic.judge(
            lufsBefore: nil,
            peakDb: nil,
            gainDb: 0
        ) == .silent)
    }

    @Test
    func veryQuietWhenLufsAfterGainIsBelowMinus35() {
        #expect(SilentSoundLogic.judge(
            lufsBefore: -50,
            peakDb: -20,
            gainDb: 10
        ) == .veryQuiet)
        #expect(SilentSoundLogic.judge(
            lufsBefore: -50,
            peakDb: -20,
            gainDb: 20
        ) == .ok)
    }

    @Test
    func boundaryIsInclusive() {
        #expect(SilentSoundLogic.judge(
            lufsBefore: -35,
            peakDb: -10,
            gainDb: 0
        ) == .ok)
        #expect(SilentSoundLogic.judge(
            lufsBefore: -30,
            peakDb: -60,
            gainDb: 0
        ) == .ok)
    }

    @Test
    func scannerMarksSilentAndVeryQuietAlarms() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("silent-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let silentURL = dir.appendingPathComponent("silent.caf")
        let quietURL = dir.appendingPathComponent("quiet.caf")
        try Data("silent".utf8).write(to: silentURL)
        try Data("quiet".utf8).write(to: quietURL)

        let entries = [
            AlarmEntry(soundFileName: "silent.caf"),
            AlarmEntry(soundFileName: "quiet.caf"),
            AlarmEntry(soundFileName: "ok.caf"),
            AlarmEntry(soundFileName: "silent.caf", playlistID: UUID())
        ]
        let okURL = dir.appendingPathComponent("ok.caf")
        try Data("ok".utf8).write(to: okURL)

        let ids = SilentAlarmScanner.silentAlarmIDs(
            entries: entries,
            soundsDirectory: dir,
            measure: { url in
                switch url.lastPathComponent {
                case "silent.caf":
                    return nil
                case "quiet.caf":
                    return LoudnessMeter.Measurement(lufs: -45, peakDb: -10)
                default:
                    return LoudnessMeter.Measurement(lufs: -20, peakDb: -2)
                }
            }
        )
        #expect(ids.contains(entries[0].id))
        #expect(ids.contains(entries[1].id))
        #expect(!ids.contains(entries[2].id))
        #expect(!ids.contains(entries[3].id))
    }

    @Test
    func analyticsLevelsAreStable() {
        #expect(SilentSoundLevel.silent.rawValue == "silent")
        #expect(SilentSoundLevel.veryQuiet.rawValue == "very_quiet")
        #expect(SilentSoundAction.otherSound.rawValue == "other_sound")

        let props = AnalyticsEvent.silentSoundBlocked(
            level: .silent,
            source: .audio,
            action: .reselect
        ).properties
        #expect(props["level"] as? String == "silent")
        #expect(props["source"] as? String == "audio")
        #expect(props["action"] as? String == "reselect")
    }
}
