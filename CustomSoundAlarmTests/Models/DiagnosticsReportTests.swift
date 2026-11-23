import Testing
import Foundation
@testable import CustomSoundAlarm

/// 診断 JSON の生成（#255）。
struct DiagnosticsReportTests {

    private func makeJSON(
        alarms: [AlarmEntry] = [],
        sounds: [AlarmSound] = [],
        history: [String] = []
    ) -> String {
        let data = DiagnosticsReportBuilder.makeJSON(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            timeZone: TimeZone(identifier: "Asia/Tokyo")!,
            appVersion: "1.8.4",
            build: "42",
            osVersion: "26.5",
            deviceModel: "iPhone (iPhone18,1)",
            localeIdentifier: "ja_JP",
            alarmKitAuthorization: "authorized",
            alarmKitRegisteredCount: 2,
            alarms: alarms,
            sounds: sounds,
            measurements: [:],
            historyLines: history,
            postHogDistinctID: "anon-123",
            audioOutputs: ["AVAudioSessionPortBuiltInSpeaker"]
        )
        return String(decoding: data, as: UTF8.self)
    }

    @Test
    func jsonDoesNotContainFileNamesOrDisplayNames() throws {
        let alarm = AlarmEntry(
            hour: 7,
            minute: 5,
            label: "My secret label",
            repeatWeekdays: [2, 3],
            soundFileName: "secret-file.caf"
        )
        let sound = AlarmSound(
            name: "Secret song title",
            fileName: "secret-file.caf",
            durationSeconds: 3,
            lufsAtImport: -20,
            gainDbAtImport: 6
        )
        let history = [
            #"{"event":"alarm_fired","ts":"2026-11-19T07:05:00+09:00","properties":{"sound_name":"Secret song title","file_name":"secret-file.caf","label":"My secret label","alarm_time":"07:05","list_on_times":"07:05"}}"#
        ]
        let json = makeJSON(alarms: [alarm], sounds: [sound], history: history)

        #expect(!json.lowercased().contains("secret"))
        #expect(!json.contains("My secret label"))
        #expect(!json.contains("secret-file.caf"))
        #expect(!json.contains("Secret song title"))
        // 番号と時刻は残る
        #expect(json.contains("\"sound_number\" : 1"))
        #expect(json.contains("\"number\" : 1"))
        #expect(json.contains("\"time\" : \"07:05\""))
        // 履歴からも名前らしきキーだけ落ちる
        #expect(json.contains("\"alarm_time\" : \"07:05\""))
    }

    @Test
    func historyIsLimitedTo200Lines() throws {
        let lines = (0..<250).map { index in
            #"{"event":"e\#(index)","properties":{"n":\#(index)}}"#
        }
        let object = DiagnosticsReportBuilder.makeObject(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            timeZone: TimeZone(identifier: "Asia/Tokyo")!,
            appVersion: "1.8.4",
            build: "42",
            osVersion: "26.5",
            deviceModel: "iPhone",
            localeIdentifier: "ja_JP",
            alarmKitAuthorization: "authorized",
            alarmKitRegisteredCount: nil,
            alarms: [],
            sounds: [],
            measurements: [:],
            historyLines: lines,
            postHogDistinctID: nil,
            audioOutputs: []
        )
        let history = try #require(object["history"] as? [[String: Any]])
        #expect(history.count == 200)
        #expect(history.first?["event"] as? String == "e50")
        #expect(history.last?["event"] as? String == "e249")
    }

    @Test
    func jsonCanBeGeneratedWithoutHistory() throws {
        let json = makeJSON()
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        #expect((object["history"] as? [Any])?.isEmpty == true)
        #expect(object["schema_version"] as? Int == DiagnosticsReportBuilder.schemaVersion)
        #expect(object["generated_at"] as? String != nil)
        #expect(object["time_zone"] as? String == "Asia/Tokyo")
    }

    @Test
    func recentHistoryLinesReadsOnlyTheNewest200() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let text = (0..<250).map { #"{"event":"e\#($0)"}"# }.joined(separator: "\n") + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)

        let lines = AlarmLocalHistoryStore.recentLines(limit: 200, fileURL: url)
        #expect(lines.count == 200)
        #expect(lines.first?.contains("\"e50\"") == true)
        #expect(lines.last?.contains("\"e249\"") == true)

        let missing = url.deletingLastPathComponent()
            .appendingPathComponent("missing-\(UUID().uuidString).jsonl")
        #expect(AlarmLocalHistoryStore.recentLines(limit: 200, fileURL: missing).isEmpty)
    }

    @Test
    func playlistAlarmHasNoSoundNumber() throws {
        let playlistAlarm = AlarmEntry(hour: 6, minute: 30, playlistID: UUID())
        let object = DiagnosticsReportBuilder.makeObject(
            generatedAt: Date(),
            timeZone: .current,
            appVersion: "1.8.4",
            build: "42",
            osVersion: "26.5",
            deviceModel: "iPhone",
            localeIdentifier: "en_US",
            alarmKitAuthorization: "denied",
            alarmKitRegisteredCount: 0,
            alarms: [playlistAlarm],
            sounds: [AlarmSound(name: "Song", fileName: "song.caf")],
            measurements: [:],
            historyLines: [],
            postHogDistinctID: nil,
            audioOutputs: []
        )
        let alarms = try #require(object["alarms"] as? [[String: Any]])
        #expect(alarms[0]["uses_playlist"] as? Bool == true)
        #expect(alarms[0]["sound_number"] == nil)
    }
}
