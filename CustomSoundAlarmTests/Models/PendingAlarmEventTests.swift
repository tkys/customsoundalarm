import Testing
import Foundation
import AlarmKit
@testable import CustomSoundAlarm

// MARK: - AlarmEventBufferTests

/// AlarmEventBuffer（App Group UserDefaults を使った Intent 間イベントバッファ）
/// の enqueue / dequeueAll を、隔離された UserDefaults インスタンスで検証する。
struct AlarmEventBufferTests {
    let testDefaults: UserDefaults

    init() {
        let suiteName = "test.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
    }

    @Test
    func enqueueAndDequeueSingleEvent() {
        let event = PendingAlarmEvent(name: "alarm_stopped", properties: ["alarm_id": "abc"], timestamp: Date())
        AlarmEventBuffer.enqueue(event, defaults: testDefaults)

        let dequeued = AlarmEventBuffer.dequeueAll(defaults: testDefaults)
        #expect(dequeued.count == 1)
        #expect(dequeued[0].name == "alarm_stopped")
        #expect(dequeued[0].properties["alarm_id"] == "abc")
    }

    @Test
    func enqueueAndDequeueMultipleEvents() {
        AlarmEventBuffer.enqueue(PendingAlarmEvent(name: "alarm_stopped", properties: [:], timestamp: Date()), defaults: testDefaults)
        AlarmEventBuffer.enqueue(PendingAlarmEvent(name: "alarm_fired", properties: [:], timestamp: Date()), defaults: testDefaults)

        let dequeued = AlarmEventBuffer.dequeueAll(defaults: testDefaults)
        #expect(dequeued.count == 2)
        #expect(dequeued[0].name == "alarm_stopped")
        #expect(dequeued[1].name == "alarm_fired")
    }

    @Test
    func dequeueAllClearsBuffer() {
        AlarmEventBuffer.enqueue(PendingAlarmEvent(name: "alarm_stopped", properties: [:], timestamp: Date()), defaults: testDefaults)
        let first = AlarmEventBuffer.dequeueAll(defaults: testDefaults)
        #expect(first.count == 1)

        let second = AlarmEventBuffer.dequeueAll(defaults: testDefaults)
        #expect(second.isEmpty)
    }

    @Test
    func dequeueAllWhenEmptyReturnsEmpty() {
        #expect(AlarmEventBuffer.dequeueAll(defaults: testDefaults).isEmpty)
    }

    @Test
    func eventsPersistAcrossInstances() {
        AlarmEventBuffer.enqueue(PendingAlarmEvent(name: "alarm_stopped", properties: ["k": "v"], timestamp: Date()), defaults: testDefaults)

        let events = AlarmEventBuffer.dequeueAll(defaults: testDefaults)
        #expect(events.count == 1)
        #expect(events[0].properties["k"] == "v")
    }

    @Test
    func flushPendingAlarmEvents_sendsBufferedEventsAtTheirTimestamp() {
        let stoppedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let secondAt = stoppedAt.addingTimeInterval(60)
        AlarmEventBuffer.enqueue(
            PendingAlarmEvent(name: "alarm_stopped", properties: [:], hour: 7, timestamp: stoppedAt),
            defaults: testDefaults
        )
        AlarmEventBuffer.enqueue(
            PendingAlarmEvent(name: "alarm_stopped", properties: [:], hour: 8, timestamp: secondAt),
            defaults: testDefaults
        )

        let mock = MockBackend()
        let service = AnalyticsService(backend: mock)
        service.flushPendingAlarmEvents(defaults: testDefaults)

        #expect(mock.captureCount == 2)
        #expect(mock.captures[0].event == "alarm_stopped")
        #expect(mock.captures[0].timestamp == stoppedAt)
        #expect(mock.captures[0].properties?["timestamp"] as? TimeInterval == stoppedAt.timeIntervalSince1970)
        #expect(mock.captures[0].properties?["hour"] as? Int == 7)
        #expect(mock.captures[1].event == "alarm_stopped")
        #expect(mock.captures[1].timestamp == secondAt)
        #expect(mock.captures[1].properties?["hour"] as? Int == 8)
        #expect(AlarmEventBuffer.dequeueAll(defaults: testDefaults).isEmpty)
    }

    @Test
    func snoozedEntryID_roundTripThroughAppGroup() {
        // Regression test for C: entryID must survive removal and re-insert
        // (.countdown → release → .countdown should record 2x)
        let uid = UUID()
        defer {
            var cleanup = AppGroup.snoozedAlarmEntryIDs
            cleanup.remove(uid)
            AppGroup.snoozedAlarmEntryIDs = cleanup
        }

        // First insertion (simulates .countdown)
        var ids = AppGroup.snoozedAlarmEntryIDs
        ids.insert(uid)
        AppGroup.snoozedAlarmEntryIDs = ids
        #expect(AppGroup.snoozedAlarmEntryIDs.contains(uid))

        // Removal (simulates .countdown released)
        ids = AppGroup.snoozedAlarmEntryIDs
        ids.remove(uid)
        AppGroup.snoozedAlarmEntryIDs = ids
        #expect(!AppGroup.snoozedAlarmEntryIDs.contains(uid))

        // Re-insertion (simulates .countdown again)
        ids = AppGroup.snoozedAlarmEntryIDs
        ids.insert(uid)
        AppGroup.snoozedAlarmEntryIDs = ids
        #expect(AppGroup.snoozedAlarmEntryIDs.contains(uid))
    }

    @Test
    func enqueueBeyondCapacity_prunesOldest() {
        // 上限100件を超えたら古いものが削除される
        for i in 0..<110 {
            AlarmEventBuffer.enqueue(
                PendingAlarmEvent(name: "test", properties: ["i": String(i)], timestamp: Date()),
                defaults: testDefaults
            )
        }

        let dequeued = AlarmEventBuffer.dequeueAll(defaults: testDefaults)
        #expect(dequeued.count == 100)

        // 最初の10件は削除されているので、"0" は無い
        let firstI = dequeued[0].properties["i"]
        #expect(firstI == "10")

        // 最後の1件は "109"
        let lastI = dequeued[99].properties["i"]
        #expect(lastI == "109")
    }

    @Test
    func flushPendingAlarmEvents_whenEmpty_isNoOp() {
        let mock = MockBackend()
        let service = AnalyticsService(backend: mock)

        service.flushPendingAlarmEvents()

        #expect(mock.captureCount == 0)
    }
}

// MARK: - 発火時刻・重複防止（#263）

struct AlarmFireOccurrenceTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int, day: Int = 16) -> Date {
        calendar.date(from: DateComponents(
            year: 2026,
            month: 11,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    @Test
    func fixedScheduleUsesExactDate() {
        let fireDate = date(7, 0)
        let schedule = Alarm.Schedule.fixed(fireDate)
        #expect(AlarmFireOccurrence.date(for: schedule, now: date(7, 5), calendar: calendar) == fireDate)
    }

    @Test
    func relativeNeverUsesTodayWhenTheTimeHasPassed() {
        let schedule = Alarm.Schedule.relative(.init(
            time: .init(hour: 7, minute: 0),
            repeats: .never
        ))
        #expect(
            AlarmFireOccurrence.date(for: schedule, now: date(7, 5), calendar: calendar)
                == date(7, 0)
        )
    }

    @Test
    func relativeNeverUsesYesterdayBeforeTheTime() {
        let schedule = Alarm.Schedule.relative(.init(
            time: .init(hour: 7, minute: 0),
            repeats: .never
        ))
        #expect(
            AlarmFireOccurrence.date(for: schedule, now: date(6, 55), calendar: calendar)
                == date(7, 0, day: 15)
        )
    }

    @Test
    func relativeWeeklyUsesTheMostRecentMatchingWeekday() {
        // 2026-11-16 は月曜
        let schedule = Alarm.Schedule.relative(.init(
            time: .init(hour: 7, minute: 0),
            repeats: .weekly([.monday])
        ))
        #expect(
            AlarmFireOccurrence.date(for: schedule, now: date(7, 5), calendar: calendar)
                == date(7, 0)
        )
    }

    @Test
    func relativeWeeklyUsesPreviousWeekBeforeTheTime() {
        let schedule = Alarm.Schedule.relative(.init(
            time: .init(hour: 7, minute: 0),
            repeats: .weekly([.monday])
        ))
        #expect(
            AlarmFireOccurrence.date(for: schedule, now: date(6, 55), calendar: calendar)
                == date(7, 0, day: 9)
        )
    }
}

struct AlarmFireTrackerTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "test.unique.\(UUID().uuidString)")!
    }

    @Test
    func markIfNeededReturnsTrueOnlyOnce() {
        let defaults = defaults()
        let occurrence = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(AlarmFireTracker.markIfNeeded(
            alarmUID: "uid-a", occurrence: occurrence, defaults: defaults
        ))
        #expect(!AlarmFireTracker.markIfNeeded(
            alarmUID: "uid-a", occurrence: occurrence, defaults: defaults
        ))
        #expect(AlarmFireTracker.hasReported(
            alarmUID: "uid-a", occurrence: occurrence, defaults: defaults
        ))
    }

    @Test
    func observerReportedOccurrenceIsNotBackfilled() {
        let defaults = defaults()
        let occurrence = Date(timeIntervalSince1970: 1_700_000_000)
        // observer が起動中に先に送った
        #expect(AlarmFireTracker.markIfNeeded(
            alarmUID: "uid-observer", occurrence: occurrence, defaults: defaults
        ))
        // そのあと止めても stopped の alarm_fired は積まない
        #expect(!AlarmFireTracker.markIfNeeded(
            alarmUID: "uid-observer", occurrence: occurrence, defaults: defaults
        ))
    }

    @Test
    func sameOccurrenceAfterSnoozeIsNotCountedAgain() {
        let defaults = defaults()
        let occurrence = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(AlarmFireTracker.markIfNeeded(
            alarmUID: "uid-snooze", occurrence: occurrence, defaults: defaults
        ))
        // スヌーズ後の再停止でも発火予定時刻は同じ
        #expect(!AlarmFireTracker.markIfNeeded(
            alarmUID: "uid-snooze", occurrence: occurrence, defaults: defaults
        ))
    }

    @Test
    func nextOccurrenceIsCountedAgain() {
        let defaults = defaults()
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        let next = first.addingTimeInterval(24 * 60 * 60)
        #expect(AlarmFireTracker.markIfNeeded(
            alarmUID: "uid-next", occurrence: first, defaults: defaults
        ))
        #expect(AlarmFireTracker.markIfNeeded(
            alarmUID: "uid-next", occurrence: next, defaults: defaults
        ))
    }

    @Test
    func differentAlarmUIDIsCountedSeparately() {
        let defaults = defaults()
        let occurrence = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(AlarmFireTracker.markIfNeeded(
            alarmUID: "uid-one", occurrence: occurrence, defaults: defaults
        ))
        #expect(AlarmFireTracker.markIfNeeded(
            alarmUID: "uid-two", occurrence: occurrence, defaults: defaults
        ))
    }

    @Test
    func occurrenceIsRoundedToTheMinute() {
        let defaults = defaults()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(AlarmFireTracker.markIfNeeded(
            alarmUID: "uid-round", occurrence: base, defaults: defaults
        ))
        #expect(!AlarmFireTracker.markIfNeeded(
            alarmUID: "uid-round",
            occurrence: base.addingTimeInterval(30),
            defaults: defaults
        ))
    }
}

struct AlarmFiredBackfillTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func stoppedEventKeepsAlarmFiredShape() {
        let entry = AlarmEntry(
            hour: 7,
            minute: 0,
            repeatWeekdays: [2, 3],
            soundFileName: "PresetBell.caf"
        )
        let context = AlarmHistoryLogic.context(for: entry, now: now)
        let event = AlarmFiredBackfill.event(
            entry: entry,
            soundMode: .single,
            context: context
        )
        let props = event.properties
        #expect(event.name == "alarm_fired")
        #expect(props["detection"] as? String == "stopped")
        #expect(props["was_app_foreground"] as? Bool == false)
        #expect(props["is_repeating"] as? Bool == true)
        #expect(props["hour"] as? Int == 7)
    }

    @Test
    func oneTimeAlarmIsNotRepeating() {
        let entry = AlarmEntry(hour: 7, minute: 0, soundFileName: "PresetBell.caf")
        let context = AlarmHistoryLogic.context(for: entry, now: now)
        let event = AlarmFiredBackfill.event(
            entry: entry,
            soundMode: .single,
            context: context
        )
        #expect(event.properties["is_repeating"] as? Bool == false)
    }

    @Test
    func pendingEventKeepsStopTimeAndBoolTypes() {
        let entry = AlarmEntry(hour: 7, minute: 0, soundFileName: "PresetBell.caf")
        let context = AlarmHistoryLogic.context(for: entry, now: now)
        let pending = AlarmFiredBackfill.pendingEvent(
            entry: entry,
            stoppedAt: now,
            soundMode: .single,
            context: context
        )
        #expect(pending.name == "alarm_fired")
        #expect(pending.timestamp == now)
        #expect(pending.postHogProperties["detection"] as? String == "stopped")
        #expect(pending.postHogProperties["is_repeating"] as? Bool == false)
        #expect(pending.postHogProperties["was_app_foreground"] as? Bool == false)
    }
}

// MARK: - MockBackend (local)

struct PendingAlarmEventPropertiesTests {
    @Test
    func postHogProperties_keepsBoolTypes() {
        let event = PendingAlarmEvent(
            name: "alarm_fired",
            properties: ["detection": "stopped"],
            boolProperties: [
                "was_app_foreground": false,
                "is_repeating": true
            ],
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let props = event.postHogProperties
        #expect(props["detection"] as? String == "stopped")
        #expect(props["was_app_foreground"] as? Bool == false)
        #expect(props["is_repeating"] as? Bool == true)
    }

    @Test
    func oldJSONWithoutBoolProperties_decodes() throws {
        let json = """
        {"name":"alarm_stopped","properties":{},"hour":7,"timestamp":0}
        """
        let data = try #require(json.data(using: .utf8))
        let event = try JSONDecoder().decode(PendingAlarmEvent.self, from: data)
        #expect(event.name == "alarm_stopped")
        #expect(event.boolProperties == nil)
    }
}

/// このファイル内で使用するモックバックエンド。
private final class MockBackend: AnalyticsBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var _captures: [(event: String, properties: [String: Any]?, timestamp: Date?)] = []

    var captures: [(event: String, properties: [String: Any]?, timestamp: Date?)] {
        lock.withLock { _captures }
    }

    var captureCount: Int {
        lock.withLock { _captures.count }
    }

    func capture(_ event: String, properties: [String: Any]?, timestamp: Date?) {
        lock.withLock {
            _captures.append((event, properties, timestamp))
        }
    }

    func setUserProperties(_ properties: [String: Any]) {}

    @Test
    func postHogProperties_mergesIntProperties() {
        let event = PendingAlarmEvent(
            name: "backup_alarm_stopped",
            properties: [:],
            intProperties: ["minutes": 15, "snoozes_before": 2],
            hour: 7,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let props = event.postHogProperties
        #expect(props["hour"] as? Int == 7)
        #expect(props["minutes"] as? Int == 15)
        #expect(props["snoozes_before"] as? Int == 2)
        #expect(props["timestamp"] as? TimeInterval == 1_700_000_000)
    }

    @Test
    func pendingEvent_oldJSONWithoutIntProperties_decodes() throws {
        let json = """
        {"name":"alarm_stopped","properties":{},"hour":7,"timestamp":0}
        """
        let data = try #require(json.data(using: .utf8))
        let event = try JSONDecoder().decode(PendingAlarmEvent.self, from: data)
        #expect(event.name == "alarm_stopped")
        #expect(event.intProperties == nil)
    }
}
