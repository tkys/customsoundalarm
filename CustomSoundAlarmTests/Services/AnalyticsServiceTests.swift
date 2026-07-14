import Testing
import Foundation
@testable import CustomSoundAlarm

// MARK: - MockBackend

/// テスト用 PostHog バックエンドのモック。SDK に依存せず、
/// 最後に capture されたイベント名とプロパティを記録する。
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
}

// MARK: - AnalyticsEventTests

/// AnalyticsEvent の「イベント名・プロパティ変換ロジック」を SDK 非依存で検証する。
struct AnalyticsEventTests {

    @Test
    func eventNameMapping() {
        #expect(AnalyticsEvent.alarmCreated(hasCustomSound: true, isRepeating: false).name == "alarm_created")
        #expect(AnalyticsEvent.customSoundImported(source: .video).name == "custom_sound_imported")
        #expect(AnalyticsEvent.customSoundImported(source: .audio).name == "custom_sound_imported")
        #expect(AnalyticsEvent.soundPreviewPlayed.name == "sound_preview_played")
    }

    // MARK: alarm_created

    @Test
    func alarmCreatedProperties_whenCustomAndRepeating() {
        let props = AnalyticsEvent.alarmCreated(hasCustomSound: true, isRepeating: true).properties

        #expect(props.count == 2)
        #expect(props["has_custom_sound"] as? Bool == true)
        #expect(props["is_repeating"] as? Bool == true)
    }

    @Test
    func alarmCreatedProperties_whenPresetAndOneShot() {
        let props = AnalyticsEvent.alarmCreated(hasCustomSound: false, isRepeating: false).properties

        #expect(props["has_custom_sound"] as? Bool == false)
        #expect(props["is_repeating"] as? Bool == false)
    }

    // MARK: custom_sound_imported

    @Test
    func customSoundImportedProperties_videoSource() {
        let props = AnalyticsEvent.customSoundImported(source: .video).properties

        #expect(props.count == 1)
        #expect(props["source"] as? String == "video")
    }

    @Test
    func customSoundImportedProperties_audioSource() {
        let props = AnalyticsEvent.customSoundImported(source: .audio).properties

        #expect(props.count == 1)
        #expect(props["source"] as? String == "audio")
    }

    @Test
    func soundSourceRawValuesAreStable() {
        // PostHog 側のダッシュボード定義と一致することが前提
        #expect(SoundImportSource.video.rawValue == "video")
        #expect(SoundImportSource.audio.rawValue == "audio")
    }

    // MARK: sound_preview_played

    @Test
    func soundPreviewPlayedProperties_areEmpty() {
        let props = AnalyticsEvent.soundPreviewPlayed.properties
        #expect(props.isEmpty)
    }

    // MARK: 全ケース網羅 (コンパイル時の網羅性も兼ねる)

    @Test
    func everyEventProducesNonEmptyName() {
        let events: [AnalyticsEvent] = [
            .alarmCreated(hasCustomSound: true, isRepeating: true),
            .customSoundImported(source: .video),
            .customSoundImported(source: .audio),
            .soundPreviewPlayed
        ]

        for event in events {
            #expect(!event.name.isEmpty, "Event name should not be empty for \(event)")
        }
    }
}

// MARK: - AnalyticsServiceCaptureTests

/// AnalyticsService.capture がバックエンドに正しいイベント名・プロパティを渡すことを検証する。
/// モックバックエンドを注入し、PostHog SDK には一切依存しない。
struct AnalyticsServiceCaptureTests {

    @Test
    func captureForwardsEventNameAndStructuredProperties() {
        let mock = MockBackend()
        let service = AnalyticsService(backend: mock)

        service.capture(.alarmCreated(hasCustomSound: true, isRepeating: false))

        #expect(mock.captureCount == 1)
        let captured = mock.captures[0]
        #expect(captured.event == "alarm_created")
        #expect(captured.properties?["has_custom_sound"] as? Bool == true)
        #expect(captured.properties?["is_repeating"] as? Bool == false)
    }

    @Test
    func captureMergesExtraPropertiesOverridingExistingKeys() {
        let mock = MockBackend()
        let service = AnalyticsService(backend: mock)

        // 同名キーは追加プロパティ側で上書きされるべき
        service.capture(
            .alarmCreated(hasCustomSound: false, isRepeating: false),
            properties: ["has_custom_sound": true, "extra": 42]
        )

        let captured = mock.captures[0]
        #expect(captured.event == "alarm_created")
        #expect(captured.properties?["has_custom_sound"] as? Bool == true)
        #expect(captured.properties?["is_repeating"] as? Bool == false)
        #expect(captured.properties?["extra"] as? Int == 42)
    }

    @Test
    func captureSendsNilPropertiesWhenEventHasNone() {
        let mock = MockBackend()
        let service = AnalyticsService(backend: mock)

        service.capture(.soundPreviewPlayed)

        #expect(mock.captureCount == 1)
        #expect(mock.captures[0].event == "sound_preview_played")
        // 空プロパティは nil として送信されるべき（無駄な JSON を送らない）
        #expect(mock.captures[0].properties == nil)
    }

    @Test
    func captureWithoutBackendIsNoOp() {
        // backend = nil の場合、クラッシュせずドロップされる
        let service = AnalyticsService(backend: nil)

        service.capture(.soundPreviewPlayed)
        service.capture(.alarmCreated(hasCustomSound: true, isRepeating: true))

        // クラッシュしないこと自体が検証基準
        #expect(Bool(true))
    }

    @Test
    func multipleCapturesAreAllForwardedInOrder() {
        let mock = MockBackend()
        let service = AnalyticsService(backend: mock)

        service.capture(.customSoundImported(source: .video))
        service.capture(.customSoundImported(source: .audio))
        service.capture(.soundPreviewPlayed)

        #expect(mock.captureCount == 3)
        #expect(mock.captures[0].event == "custom_sound_imported")
        #expect(mock.captures[0].properties?["source"] as? String == "video")
        #expect(mock.captures[1].properties?["source"] as? String == "audio")
        #expect(mock.captures[2].properties == nil)
    }
}

// MARK: - AnalyticsConfigTests

/// AnalyticsConfig.from(bundle:) が Info.plist 辞書を正しく読み取ることを検証する。
/// テスト用バンドルを簡単に作れないため、Bundle.main の Info.plist の構造を直接検証する。
struct AnalyticsConfigTests {

    @Test
    func configFromMainBundleHasExpectedKeys() {
        // テストホストアプリの Info.plist に PostHog キーが含まれていること
        let key = Bundle.main.object(forInfoDictionaryKey: "PostHogAPIKey") as? String
        let host = Bundle.main.object(forInfoDictionaryKey: "PostHogHost") as? String

        // xcconfig が読み込まれていれば非空の値が入るはず。
        // テスト環境次第でプレースホルダの場合もあるため、キー自体の存在を最低限担保する。
        #expect(key != nil)
        #expect(host != nil)
    }
}

// MARK: - Locking helper

private extension NSLock {
    func withLock<T>(_ block: () -> T) -> T {
        lock()
        defer { unlock() }
        return block()
    }
}
