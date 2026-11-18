import Testing
import Foundation
@testable import CustomSoundAlarm

struct AlarmHistoryTests {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }()

    private var timeZone: TimeZone { TimeZone(identifier: "Asia/Tokyo")! }

    @Test
    func contextRoundsLocalTimeAndUsesLocalWeekday() {
        let entry = AlarmEntry(hour: 7, minute: 30, repeatWeekdays: [3, 1, 2])
        let now = date(2026, 11, 18, 10, 7)
        let context = AlarmHistoryLogic.context(
            for: entry,
            now: now,
            calendar: calendar,
            timeZone: timeZone
        )

        #expect(context.alarmTime == "07:30")
        #expect(context.repeatDays == "1,2,3")
        #expect(context.localTime == "10:05")
        #expect(context.localWeekday == 4)
        #expect(context.tzOffsetMin == 540)
        #expect(context.properties["history_schema"] as? Int == 1)
    }

    @Test
    func listSnapshotSortsAndLimitsToTwenty() {
        let on = (0..<25).map { AlarmEntry(hour: 0, minute: $0, isEnabled: true) }
        let off = (0..<3).map { AlarmEntry(hour: 12, minute: $0, isEnabled: false) }
        let snapshot = AlarmHistoryLogic.listSnapshot(on + off)

        #expect(snapshot.onTimes.count == 20)
        #expect(snapshot.offTimes.count == 3)
        #expect(snapshot.onTimes.first == "00:00")
        #expect(snapshot.onTimes.last == "00:19")
        #expect(snapshot.offTimes == ["12:00", "12:01", "12:02"])
    }

    @Test
    func uidIsStableForTheSameAlarm() {
        let id = UUID()
        let first = AlarmUIDStore.uid(for: id, now: date(2026, 11, 18, 9, 0))
        let second = AlarmUIDStore.uid(for: id, now: date(2026, 11, 19, 9, 0))
        #expect(first == second)

        let created = AlarmUIDStore.creationDate(for: id)
        #expect(Calendar.current.dateComponents([.day], from: created, to: date(2026, 11, 21, 9, 0)).day == 3)
    }

    @Test
    func localHistoryKeepsOnlyTheNewestFiveThousandLines() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alarm-history-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }

        for index in 0..<5_001 {
            AlarmLocalHistoryStore.append(
                event: "alarm_fired",
                properties: ["index": index],
                now: date(2026, 11, 18, 9, 0),
                fileURL: url,
                calendar: calendar,
                timeZone: timeZone,
                trimThresholdBytes: 1
            )
        }

        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n")
        #expect(lines.count == 5_000)
        #expect(lines.first?.contains("\"index\":1") == true)
        #expect(lines.first?.contains("\"index\":0") == false)
    }

    @Test
    func localHistoryUsesUnroundedLocalTime() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alarm-history-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }

        AlarmLocalHistoryStore.append(
            event: "alarm_fired",
            properties: [:],
            now: date(2026, 11, 18, 10, 7),
            fileURL: url,
            calendar: calendar,
            timeZone: timeZone
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("\"local_time\":\"10:07\""))
        // 日付まで入った時刻（オフセット付き）が残る
        #expect(text.contains("\"ts\":\"2026-11-18T10:07:00"))
    }

    @Test
    func localHistoryAppendsWithoutRewritingBelowThreshold() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alarm-history-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }

        for index in 0..<3 {
            AlarmLocalHistoryStore.append(
                event: "alarm_toggled",
                properties: ["index": index],
                now: date(2026, 11, 18, 9, index),
                fileURL: url,
                calendar: calendar,
                timeZone: timeZone
            )
        }
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 3)
        #expect(lines.last?.contains("\"index\":2") == true)
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
