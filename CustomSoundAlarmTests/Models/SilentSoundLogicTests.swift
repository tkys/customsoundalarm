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
    func wholeFileSilentOnlyWhenMeasuredSilent() {
        #expect(SilentSoundLogic.isWholeFileSilent(
            measurement: LoudnessMeter.Measurement(lufs: -80, peakDb: -80),
            isReadable: true
        ) == true)
        #expect(SilentSoundLogic.isWholeFileSilent(
            measurement: LoudnessMeter.Measurement(lufs: -45, peakDb: -10),
            isReadable: true
        ) == false)
        // 読み込めて計測できない = 無音（#256 レビュー）
        #expect(SilentSoundLogic.isWholeFileSilent(
            measurement: nil,
            isReadable: true
        ) == true)
        // 読み込みに失敗したときは無音と断定しない
        #expect(SilentSoundLogic.isWholeFileSilent(
            measurement: nil,
            isReadable: false
        ) == false)
    }

    @Test
    func scannerMarksSilentAndVeryQuietAlarms() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("silent-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        for name in ["silent.caf", "quiet.caf", "ok.caf", "unknown.caf"] {
            try Data(name.utf8).write(to: dir.appendingPathComponent(name))
        }

        let entries = [
            AlarmEntry(soundFileName: "silent.caf"),
            AlarmEntry(soundFileName: "quiet.caf"),
            AlarmEntry(soundFileName: "ok.caf"),
            AlarmEntry(soundFileName: "unknown.caf"),
            AlarmEntry(soundFileName: "silent.caf", playlistID: UUID())
        ]

        let result = SilentAlarmScanner.scan(
            entries: entries,
            soundsDirectory: dir,
            cached: [:],
            measure: { url in
                switch url.lastPathComponent {
                case "silent.caf":
                    return LoudnessMeter.Measurement(lufs: -80, peakDb: -80)
                case "quiet.caf":
                    return LoudnessMeter.Measurement(lufs: -45, peakDb: -10)
                case "unknown.caf":
                    return nil
                default:
                    return LoudnessMeter.Measurement(lufs: -20, peakDb: -2)
                }
            }
        )
        #expect(result.levels[entries[0].id] == .silent)
        #expect(result.levels[entries[1].id] == .veryQuiet)
        #expect(result.levels[entries[2].id] == nil)
        // 計測できなかったものは警告しない（#256 レビュー）
        #expect(result.levels[entries[3].id] == nil)
        #expect(result.levels[entries[4].id] == nil)
        #expect(result.cache["unknown.caf"] == SilentSoundLevel.ok.rawValue)
    }

    @Test
    func scannerUsesCachedLevelsWithoutMeasuring() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("silent-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let silentEntry = AlarmEntry(soundFileName: "silent.caf")
        let okEntry = AlarmEntry(soundFileName: "ok.caf")
        for name in ["silent.caf", "ok.caf"] {
            try Data(name.utf8).write(to: dir.appendingPathComponent(name))
        }

        let result = SilentAlarmScanner.scan(
            entries: [silentEntry, okEntry],
            soundsDirectory: dir,
            cached: [
                "silent.caf": SilentSoundLevel.silent.rawValue,
                "ok.caf": SilentSoundLevel.ok.rawValue
            ],
            measure: { _ in
                Issue.record("cached files must not be measured again")
                return nil
            }
        )
        #expect(result.levels[silentEntry.id] == .silent)
        #expect(result.levels[okEntry.id] == nil)
        #expect(result.cache.count == 2)
    }

    @Test
    func analyticsLevelsAreStable() {
        #expect(SilentSoundLevel.silent.rawValue == "silent")
        #expect(SilentSoundLevel.veryQuiet.rawValue == "very_quiet")
        #expect(SilentSoundAction.otherSound.rawValue == "other_sound")
        #expect(SilentSoundAction.fixedExisting.rawValue == "fixed_existing")

        let props = AnalyticsEvent.silentSoundBlocked(
            level: .silent,
            source: .audio,
            action: .reselect
        ).properties
        #expect(props["level"] as? String == "silent")
        #expect(props["source"] as? String == "audio")
        #expect(props["action"] as? String == "reselect")

        let fixed = AnalyticsEvent.silentSoundBlocked(
            level: .veryQuiet,
            source: .existing,
            action: .fixedExisting
        ).properties
        #expect(fixed["action"] as? String == "fixed_existing")
        #expect(fixed["source"] as? String == "existing")
    }
}
