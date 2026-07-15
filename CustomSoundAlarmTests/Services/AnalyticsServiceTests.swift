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
        // Phase 2
        #expect(AnalyticsEvent.alarmEdited(hasCustomSound: true, isRepeating: false).name == "alarm_edited")
        #expect(AnalyticsEvent.alarmDeleted.name == "alarm_deleted")
        #expect(AnalyticsEvent.alarmPermission(status: .authorized).name == "alarm_permission")
        #expect(AnalyticsEvent.videoImportStarted.name == "video_import_started")
        #expect(AnalyticsEvent.videoImportFailed(reason: .unknown).name == "video_import_failed")
        #expect(AnalyticsEvent.alarmDuplicated.name == "alarm_duplicated")
        #expect(AnalyticsEvent.soundPickerRecentUsed.name == "sound_picker_recent_used")
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
            .soundPreviewPlayed,
            .alarmEdited(hasCustomSound: true, isRepeating: true),
            .alarmDeleted,
            .alarmPermission(status: .authorized),
            .videoImportStarted,
            .videoImportFailed(reason: .unknown),
            .alarmDuplicated,
            .soundPickerRecentUsed
        ]

        for event in events {
            #expect(!event.name.isEmpty, "Event name should not be empty for \(event)")
        }
    }

    // MARK: alarm_edited

    @Test
    func alarmEditedProperties_matchAlarmCreatedShape() {
        // 仕様: alarm_created と props を揃える（has_custom_sound / is_repeating）
        let edited = AnalyticsEvent.alarmEdited(hasCustomSound: true, isRepeating: false).properties
        let created = AnalyticsEvent.alarmCreated(hasCustomSound: true, isRepeating: false).properties

        #expect(edited.count == 2)
        #expect(Set(edited.keys) == Set(created.keys))
        #expect(edited["has_custom_sound"] as? Bool == true)
        #expect(edited["is_repeating"] as? Bool == false)
    }

    @Test
    func alarmEditedProperties_presetOneShot() {
        let props = AnalyticsEvent.alarmEdited(hasCustomSound: false, isRepeating: false).properties
        #expect(props["has_custom_sound"] as? Bool == false)
        #expect(props["is_repeating"] as? Bool == false)
    }

    // MARK: alarm_deleted

    @Test
    func alarmDeletedProperties_areEmpty() {
        #expect(AnalyticsEvent.alarmDeleted.properties.isEmpty)
    }

    // MARK: alarm_permission

    @Test
    func alarmPermissionProperties_carryStableStatus() {
        #expect(AnalyticsEvent.alarmPermission(status: .authorized).properties["status"] as? String == "authorized")
        #expect(AnalyticsEvent.alarmPermission(status: .denied).properties["status"] as? String == "denied")
        #expect(AnalyticsEvent.alarmPermission(status: .notDetermined).properties["status"] as? String == "not_determined")
        #expect(AnalyticsEvent.alarmPermission(status: .requestFailed).properties["status"] as? String == "request_failed")
        #expect(AnalyticsEvent.alarmPermission(status: .unknown).properties["status"] as? String == "unknown")
    }

    @Test
    func alarmPermissionStatusRawValuesAreStable() {
        // PostHog ダッシュボード定義と一致すること
        #expect(AlarmPermissionStatus.authorized.rawValue == "authorized")
        #expect(AlarmPermissionStatus.denied.rawValue == "denied")
        #expect(AlarmPermissionStatus.notDetermined.rawValue == "not_determined")
        #expect(AlarmPermissionStatus.requestFailed.rawValue == "request_failed")
        #expect(AlarmPermissionStatus.unknown.rawValue == "unknown")
    }

    // MARK: video_import_started

    @Test
    func videoImportStartedProperties_areEmpty() {
        #expect(AnalyticsEvent.videoImportStarted.properties.isEmpty)
    }

    // MARK: video_import_failed

    @Test
    func videoImportFailedProperties_carryStableReason() {
        let props = AnalyticsEvent.videoImportFailed(reason: .exportFailed).properties
        #expect(props.count == 1)
        #expect(props["reason"] as? String == "export_failed")
    }

    // MARK: alarm_duplicated

    @Test
    func alarmDuplicatedProperties_areEmpty() {
        #expect(AnalyticsEvent.alarmDuplicated.properties.isEmpty)
    }

    // MARK: sound_picker_recent_used

    @Test
    func soundPickerRecentUsedProperties_areEmpty() {
        #expect(AnalyticsEvent.soundPickerRecentUsed.properties.isEmpty)
    }

    @Test
    func videoImportFailureReasonRawValuesAreStable() {
        #expect(VideoImportFailureReason.noAudioTrack.rawValue == "no_audio_track")
        #expect(VideoImportFailureReason.exportSessionFailed.rawValue == "export_session_failed")
        #expect(VideoImportFailureReason.exportFailed.rawValue == "export_failed")
        #expect(VideoImportFailureReason.converterSetupFailed.rawValue == "converter_setup_failed")
        #expect(VideoImportFailureReason.conversionFailed.rawValue == "conversion_failed")
        #expect(VideoImportFailureReason.unknown.rawValue == "unknown")
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

    // MARK: Phase 2 events

    @Test
    func captureForwardsAlarmEdited() {
        let mock = MockBackend()
        let service = AnalyticsService(backend: mock)

        service.capture(.alarmEdited(hasCustomSound: true, isRepeating: true))

        #expect(mock.captureCount == 1)
        #expect(mock.captures[0].event == "alarm_edited")
        #expect(mock.captures[0].properties?["has_custom_sound"] as? Bool == true)
        #expect(mock.captures[0].properties?["is_repeating"] as? Bool == true)
    }

    @Test
    func captureForwardsAlarmDeletedWithNilProperties() {
        let mock = MockBackend()
        let service = AnalyticsService(backend: mock)

        service.capture(.alarmDeleted)

        #expect(mock.captureCount == 1)
        #expect(mock.captures[0].event == "alarm_deleted")
        #expect(mock.captures[0].properties == nil)
    }

    @Test
    func captureForwardsAlarmPermissionStatus() {
        let mock = MockBackend()
        let service = AnalyticsService(backend: mock)

        service.capture(.alarmPermission(status: .denied))

        #expect(mock.captureCount == 1)
        #expect(mock.captures[0].event == "alarm_permission")
        #expect(mock.captures[0].properties?["status"] as? String == "denied")
    }

    @Test
    func captureForwardsVideoImportStartedWithNilProperties() {
        let mock = MockBackend()
        let service = AnalyticsService(backend: mock)

        service.capture(.videoImportStarted)

        #expect(mock.captureCount == 1)
        #expect(mock.captures[0].event == "video_import_started")
        #expect(mock.captures[0].properties == nil)
    }

    @Test
    func captureForwardsVideoImportFailedWithMappedReason() {
        let mock = MockBackend()
        let service = AnalyticsService(backend: mock)

        service.capture(.videoImportFailed(reason: .noAudioTrack))

        #expect(mock.captureCount == 1)
        #expect(mock.captures[0].event == "video_import_failed")
        #expect(mock.captures[0].properties?["reason"] as? String == "no_audio_track")
    }

    @Test
    func captureForwardsAlarmDuplicatedWithNilProperties() {
        let mock = MockBackend()
        let service = AnalyticsService(backend: mock)

        service.capture(.alarmDuplicated)

        #expect(mock.captureCount == 1)
        #expect(mock.captures[0].event == "alarm_duplicated")
        #expect(mock.captures[0].properties == nil)
    }

    @Test
    func captureForwardsSoundPickerRecentUsedWithNilProperties() {
        let mock = MockBackend()
        let service = AnalyticsService(backend: mock)

        service.capture(.soundPickerRecentUsed)

        #expect(mock.captureCount == 1)
        #expect(mock.captures[0].event == "sound_picker_recent_used")
        #expect(mock.captures[0].properties == nil)
    }
}

// MARK: - VideoImportFailureReasonMappingTests

/// `VideoImportFailureReason.from(_:)` が、PII（ファイルパス等を含みうる
/// `localizedDescription`）を介さず、発生したエラーの case を安定識別子に
/// 正しくマップすることを検証する。未知エラーは `.unknown` に集約される。
struct VideoImportFailureReasonMappingTests {

    @Test
    func mapsNoAudioTrackError() {
        #expect(VideoImportFailureReason.from(VideoExtractionError.noAudioTrack) == .noAudioTrack)
    }

    @Test
    func mapsExportSessionFailedError() {
        #expect(VideoImportFailureReason.from(VideoExtractionError.exportSessionFailed) == .exportSessionFailed)
    }

    @Test
    func mapsExportFailedErrorIgnoringEmbeddedDescription() {
        // exportFailed は関連値に localizedDescription を保持しうるが、
        // reason はその値を使わず case のみで判定する
        let errorWithPossiblePII = VideoExtractionError.exportFailed("/Users/secret/path/file.m4a")
        #expect(VideoImportFailureReason.from(errorWithPossiblePII) == .exportFailed)
    }

    @Test
    func mapsConverterCreationErrors() {
        #expect(VideoImportFailureReason.from(AudioConverterError.converterCreationFailed) == .converterSetupFailed)
        #expect(VideoImportFailureReason.from(AudioConverterError.bufferCreationFailed) == .converterSetupFailed)
    }

    @Test
    func mapsConversionFailedErrorIgnoringEmbeddedDescription() {
        let errorWithPossiblePII = AudioConverterError.conversionFailed("/var/mobile/Containers/Data/secret.caf")
        #expect(VideoImportFailureReason.from(errorWithPossiblePII) == .conversionFailed)
    }

    @Test
    func mapsUnknownErrorToUnknown() {
        struct ArbitraryError: Error {}
        #expect(VideoImportFailureReason.from(ArbitraryError()) == .unknown)
    }

    @Test
    func mappedReasonNeverCarriesPathLikeContent() {
        // PII 安全の最終保証: どのエラーを入れても、reason の rawValue は
        // ホワイトリスト化された固定文字列のいずれかになる
        let allReasons = [
            VideoImportFailureReason.from(VideoExtractionError.noAudioTrack),
            VideoImportFailureReason.from(VideoExtractionError.exportSessionFailed),
            VideoImportFailureReason.from(VideoExtractionError.exportFailed("anything/with/slashes")),
            VideoImportFailureReason.from(AudioConverterError.bufferCreationFailed),
            VideoImportFailureReason.from(AudioConverterError.converterCreationFailed),
            VideoImportFailureReason.from(AudioConverterError.conversionFailed("C:\\Users\\secret")),
            VideoImportFailureReason.from(NSError(domain: "x", code: 42))
        ]

        let allowedReasons = Set([
            "no_audio_track", "export_session_failed", "export_failed",
            "converter_setup_failed", "conversion_failed", "unknown"
        ])
        for reason in allReasons {
            #expect(allowedReasons.contains(reason.rawValue), "Unexpected reason: \(reason.rawValue)")
            // パス区切り文字やドットを含まないこと（PII 混入のヒューリスティック）
            #expect(!reason.rawValue.contains("/"))
            #expect(!reason.rawValue.contains("\\"))
            #expect(!reason.rawValue.contains("."))
        }
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
