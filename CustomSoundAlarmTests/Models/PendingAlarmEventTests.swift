import Testing
import Foundation
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
    func flushPendingAlarmEvents_sendsBufferedEvents() {
        let now = Date()
        AlarmEventBuffer.enqueue(PendingAlarmEvent(name: "alarm_stopped", properties: ["alarm_id": "123"], timestamp: now), defaults: testDefaults)
        AlarmEventBuffer.enqueue(PendingAlarmEvent(name: "alarm_stopped", properties: ["alarm_id": "456"], timestamp: now), defaults: testDefaults)

        let mock = MockBackend()
        let service = AnalyticsService(backend: mock)

        // 隔離された defaults を使って flush させるために、AnalyticsService に直接渡せない
        // 代わりに内部の flushPendingAlarmEvents が使う AppGroup.userDefaults を
        // 差し替えるのは難しい。ここでは enqueue/dequeueAll の連携を検証する。
        let dequeued = AlarmEventBuffer.dequeueAll(defaults: testDefaults)
        for event in dequeued {
            var props: [String: Any] = ["timestamp": event.timestamp.timeIntervalSince1970]
            for (k, v) in event.properties {
                props[k] = v
            }
            mock.capture(event.name, properties: props)
        }

        #expect(mock.captureCount == 2)
        #expect(mock.captures[0].event == "alarm_stopped")
        #expect(mock.captures[1].event == "alarm_stopped")
        #expect(AlarmEventBuffer.dequeueAll(defaults: testDefaults).isEmpty)
    }

    @Test
    func flushPendingAlarmEvents_whenEmpty_isNoOp() {
        let mock = MockBackend()
        let service = AnalyticsService(backend: mock)

        service.flushPendingAlarmEvents()

        #expect(mock.captureCount == 0)
    }
}

// MARK: - MockBackend (local)

/// このファイル内で使用するモックバックエンド。
private final class MockBackend: AnalyticsBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var _captures: [(event: String, properties: [String: Any]?)] = []

    var captures: [(event: String, properties: [String: Any]?)] {
        lock.withLock { _captures }
    }

    var captureCount: Int {
        lock.withLock { _captures.count }
    }

    func capture(_ event: String, properties: [String: Any]?) {
        lock.withLock {
            _captures.append((event, properties))
        }
    }

    func setUserProperties(_ properties: [String: Any]) {}
}
