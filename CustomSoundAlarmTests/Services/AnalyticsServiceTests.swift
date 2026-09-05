import Testing
import Foundation
@testable import CustomSoundAlarm

// MARK: - MockBackend

/// テスト用 PostHog バックエンドのモック。SDK に依存せず、
/// 最後に capture されたイベント名とプロパティを記録する。
private final class MockBackend: AnalyticsBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var _captures: [(event: String, properties: [String: Any]?)] = []
    private var _userProperties: [String: Any] = [:]

    var captures: [(event: String, properties: [String: Any]?)] {
        lock.withLock { _captures }
    }

    var captureCount: Int {
        lock.withLock { _captures.count }
    }

    var userProperties: [String: Any] {
        lock.withLock { _userProperties }
    }

    func capture(_ event: String, properties: [String: Any]?) {
        lock.withLock {
            _captures.append((event, properties))
        }
    }

    func setUserProperties(_ properties: [String: Any]) {
        lock.withLock {
            _userProperties = properties
        }
    }
}

// MARK: - AnalyticsEventTests

/// AnalyticsEvent の「イベント名・プロパティ変換ロジック」を SDK 非依存で検証する。
struct AnalyticsEventTests {

    @Test
    func eventNameMapping() {
        #expect(AnalyticsEvent.alarmCreated(hasCustomSound: true, isRepeating: false, snoozeMinutes: 0).name == "alarm_created")
        #expect(AnalyticsEvent.customSoundImported(source: .video).name == "custom_sound_imported")
        #expect(AnalyticsEvent.customSoundImported(source: .audio).name == "custom_sound_imported")
        #expect(AnalyticsEvent.soundPreviewPlayed.name == "sound_preview_played")
        // Phase 2
        #expect(AnalyticsEvent.alarmEdited(hasCustomSound: true, isRepeating: false, snoozeMinutes: 0).name == "alarm_edited")
        #expect(AnalyticsEvent.alarmDeleted.name == "alarm_deleted")
        #expect(AnalyticsEvent.alarmPermission(status: .authorized).name == "alarm_permission")
        #expect(AnalyticsEvent.videoImportStarted(source: .photoLibrary).name == "video_import_started")
        #expect(AnalyticsEvent.videoImportFailed(reason: .unknown).name == "video_import_failed")
        #expect(AnalyticsEvent.alarmDuplicated.name == "alarm_duplicated")
        #expect(AnalyticsEvent.soundPickerRecentUsed.name == "sound_picker_recent_used")
        // Phase 3
        #expect(AnalyticsEvent.alarmFired(wasAppForeground: true, hour: 8, isRepeating: false, detection: "observer").name == "alarm_fired")
        #expect(AnalyticsEvent.alarmStopped(hour: 8).name == "alarm_stopped")
        #expect(AnalyticsEvent.alarmSnoozed(from: "observer").name == "alarm_snoozed")
        // Phase 4（ベッドサイドモード・#68）
        #expect(AnalyticsEvent.bedsideEntered(layout: "digital_large", theme: "white", hour: 23).name == "bedside_entered")
        #expect(AnalyticsEvent.bedsideExited(durationBucket: "over_2h", exitMethod: "long_press").name == "bedside_exited")
        #expect(AnalyticsEvent.bedsideSettingChanged(setting: .layout, value: .string("minimal")).name == "bedside_setting_changed")
        // #71: バックグラウンド退出も同じイベント名
        #expect(AnalyticsEvent.bedsideExited(durationBucket: "under_1min", exitMethod: "backgrounded").name == "bedside_exited")
    }

    // MARK: alarm_created

    @Test
    func alarmCreatedProperties_whenCustomAndRepeating() {
        let props = AnalyticsEvent.alarmCreated(hasCustomSound: true, isRepeating: true, snoozeMinutes: 9).properties

        #expect(props.count == 3)
        #expect(props["has_custom_sound"] as? Bool == true)
        #expect(props["is_repeating"] as? Bool == true)
        #expect(props["snooze_minutes"] as? Int == 9)
    }

    @Test
    func alarmCreatedProperties_whenPresetAndOneShot() {
        let props = AnalyticsEvent.alarmCreated(hasCustomSound: false, isRepeating: false, snoozeMinutes: 0).properties

        #expect(props["has_custom_sound"] as? Bool == false)
        #expect(props["is_repeating"] as? Bool == false)
        #expect(props["snooze_minutes"] as? Int == 0)
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
            .alarmCreated(hasCustomSound: true, isRepeating: true, snoozeMinutes: 0),
            .customSoundImported(source: .video),
            .customSoundImported(source: .audio),
            .soundPreviewPlayed,
            .alarmEdited(hasCustomSound: true, isRepeating: true, snoozeMinutes: 0),
            .alarmDeleted,
            .alarmPermission(status: .authorized),
            .videoImportStarted(source: .photoLibrary),
            .videoImportFailed(reason: .unknown),
            .alarmDuplicated,
            .soundPickerRecentUsed,
            .alarmFired(wasAppForeground: true, hour: 8, isRepeating: false, detection: "observer"),
            .alarmStopped(hour: 8),
            .alarmSnoozed(from: "observer"),
            .bedsideEntered(layout: "digital_large", theme: "white", hour: 23),
            .bedsideExited(durationBucket: "1_5min", exitMethod: "exit_button"),
            .bedsideSettingChanged(setting: .layout, value: .string("minimal")),
            .bedsideSettingChanged(setting: .brightness, value: .number(0.8)),
            .bedsideSettingChanged(setting: .seconds, value: .bool(true)),
        ]

        for event in events {
            #expect(!event.name.isEmpty, "Event name should not be empty for \(event)")
        }
    }

    // MARK: alarm_edited

    @Test
    func alarmEditedProperties_matchAlarmCreatedShape() {
        // 仕様: alarm_created と props を揃える（has_custom_sound / is_repeating / snooze_minutes）
        let edited = AnalyticsEvent.alarmEdited(hasCustomSound: true, isRepeating: false, snoozeMinutes: 9).properties
        let created = AnalyticsEvent.alarmCreated(hasCustomSound: true, isRepeating: false, snoozeMinutes: 9).properties

        #expect(edited.count == 3)
        #expect(Set(edited.keys) == Set(created.keys))
        #expect(edited["has_custom_sound"] as? Bool == true)
        #expect(edited["is_repeating"] as? Bool == false)
        #expect(edited["snooze_minutes"] as? Int == 9)
    }

    @Test
    func alarmEditedProperties_presetOneShot() {
        let props = AnalyticsEvent.alarmEdited(hasCustomSound: false, isRepeating: false, snoozeMinutes: 0).properties
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
    func videoImportStartedProperties_containsSource() {
        let photoProps = AnalyticsEvent.videoImportStarted(source: .photoLibrary).properties
        #expect(photoProps["source"] as? String == "photo_library")

        let fileProps = AnalyticsEvent.videoImportStarted(source: .file).properties
        #expect(fileProps["source"] as? String == "file")
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

    // MARK: bedside_entered

    @Test
    func bedsideEnteredProperties_carryLayoutThemeHour() {
        let props = AnalyticsEvent.bedsideEntered(layout: "digital_large", theme: "amber", hour: 23).properties

        #expect(props.count == 3)
        #expect(props["layout"] as? String == "digital_large")
        #expect(props["theme"] as? String == "amber")
        #expect(props["hour"] as? Int == 23)
    }

    @Test
    func bedsideEnteredProperties_midnightHour() {
        let props = AnalyticsEvent.bedsideEntered(layout: "minimal", theme: "white", hour: 0).properties
        #expect(props["hour"] as? Int == 0)
    }

    // MARK: bedside_exited

    @Test
    func bedsideExitedProperties_carryBucketAndMethod() {
        let props = AnalyticsEvent.bedsideExited(durationBucket: "under_1min", exitMethod: "exit_button").properties

        #expect(props.count == 2)
        #expect(props["duration_bucket"] as? String == "under_1min")
        #expect(props["exit_method"] as? String == "exit_button")
    }

    @Test
    func bedsideExitedProperties_longPressMethod() {
        let props = AnalyticsEvent.bedsideExited(durationBucket: "over_2h", exitMethod: "long_press").properties
        #expect(props["exit_method"] as? String == "long_press")
    }

    @Test
    func bedsideExitedProperties_backgroundedMethod() {
        // #71: バックグラウンド化による退出（exit_button / long_press と区別）
        let props = AnalyticsEvent.bedsideExited(durationBucket: "under_1min", exitMethod: "backgrounded").properties
        #expect(props["exit_method"] as? String == "backgrounded")
    }

    @Test
    func bedsideExitMethodRawValuesAreStable() {
        #expect(BedsideExitMethod.exitButton.rawValue == "exit_button")
        #expect(BedsideExitMethod.longPress.rawValue == "long_press")
        #expect(BedsideExitMethod.backgrounded.rawValue == "backgrounded")
    }

    // MARK: bedside_setting_changed

    @Test
    func bedsideSettingChangedProperties_stringValue() {
        let props = AnalyticsEvent.bedsideSettingChanged(setting: .layout, value: .string("flip_clock")).properties

        #expect(props.count == 2)
        #expect(props["setting"] as? String == "layout")
        #expect(props["value"] as? String == "flip_clock")
    }

    @Test
    func bedsideSettingChangedProperties_numberValue() {
        let props = AnalyticsEvent.bedsideSettingChanged(setting: .brightness, value: .number(0.6)).properties

        #expect(props["setting"] as? String == "brightness")
        let value = props["value"] as? Double
        #expect(value != nil)
        // 浮動小数点は許容誤差で比較（#61）
        if let value {
            #expect(abs(value - 0.6) < 0.0001)
        }
    }

    @Test
    func bedsideSettingChangedProperties_boolValue() {
        let props = AnalyticsEvent.bedsideSettingChanged(setting: .seconds, value: .bool(true)).properties
        #expect(props["setting"] as? String == "seconds")
        #expect(props["value"] as? Bool == true)
    }

    @Test
    func bedsideSettingRawValuesAreStable() {
        // PostHog ダッシュボード定義と一致すること
        #expect(BedsideSetting.layout.rawValue == "layout")
        #expect(BedsideSetting.theme.rawValue == "theme")
        #expect(BedsideSetting.brightness.rawValue == "brightness")
        #expect(BedsideSetting.fontScale.rawValue == "font_scale")
        #expect(BedsideSetting.elements.rawValue == "elements")
        #expect(BedsideSetting.seconds.rawValue == "seconds")
    }
}

    // MARK: alarm_fired

    @Test
    func alarmFiredProperties_foregroundRepeatingObserver() {
        let props = AnalyticsEvent.alarmFired(wasAppForeground: true, hour: 14, isRepeating: true, detection: "observer").properties
        #expect(props.count == 4)
        #expect(props["was_app_foreground"] as? Bool == true)
        #expect(props["hour"] as? Int == 14)
        #expect(props["is_repeating"] as? Bool == true)
        #expect(props["detection"] as? String == "observer")
    }

    @Test
    func alarmFiredProperties_backgroundOneShotReconcile() {
        let props = AnalyticsEvent.alarmFired(wasAppForeground: false, hour: 7, isRepeating: false, detection: "reconcile").properties
        #expect(props["was_app_foreground"] as? Bool == false)
        #expect(props["hour"] as? Int == 7)
        #expect(props["is_repeating"] as? Bool == false)
        #expect(props["detection"] as? String == "reconcile")
    }

    // MARK: alarm_stopped

    @Test
    func alarmStoppedProperties_hasHour() {
        let props = AnalyticsEvent.alarmStopped(hour: 7).properties
        #expect(props.count == 1)
        #expect(props["hour"] as? Int == 7)
    }

    @Test
    func alarmStoppedProperties_midnight() {
        let props = AnalyticsEvent.alarmStopped(hour: 0).properties
        #expect(props["hour"] as? Int == 0)
    }

    // MARK: alarm_snoozed

    @Test
    func alarmSnoozedProperties_fromObserver() {
        let props = AnalyticsEvent.alarmSnoozed(from: "observer").properties
        #expect(props.count == 1)
        #expect(props["from"] as? String == "observer")
    }

    @Test
    func alarmSnoozedProperties_fromReconcile() {
        let props = AnalyticsEvent.alarmSnoozed(from: "reconcile").properties
        #expect(props["from"] as? String == "reconcile")
    }

// MARK: - AnalyticsServiceCaptureTests

/// AnalyticsService.capture がバックエンドに正しいイベント名・プロパティを渡すことを検証する。
/// モックバックエンドを注入し、PostHog SDK には一切依存しない。
struct AnalyticsServiceCaptureTests {

    @Test
    func captureForwardsEventNameAndStructuredProperties() {
        let mock = MockBackend()
        let service = AnalyticsService(backend: mock)

        service.capture(.alarmCreated(hasCustomSound: true, isRepeating: false, snoozeMinutes: 0))

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
            .alarmCreated(hasCustomSound: false, isRepeating: false, snoozeMinutes: 0),
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
        service.capture(.alarmCreated(hasCustomSound: true, isRepeating: true, snoozeMinutes: 0))

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

        service.capture(.alarmEdited(hasCustomSound: true, isRepeating: true, snoozeMinutes: 0))

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
    func captureForwardsVideoImportStartedWithSource() {
        let mock = MockBackend()
        let service = AnalyticsService(backend: mock)

        service.capture(.videoImportStarted(source: .file))

        #expect(mock.captureCount == 1)
        #expect(mock.captures[0].event == "video_import_started")
        #expect(mock.captures[0].properties?["source"] as? String == "file")
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

    // MARK: Phase 3 events

    @Test
    func captureForwardsAlarmFired() {
        let mock = MockBackend()
        let service = AnalyticsService(backend: mock)

        service.capture(.alarmFired(wasAppForeground: true, hour: 10, isRepeating: false, detection: "observer"))

        #expect(mock.captureCount == 1)
        #expect(mock.captures[0].event == "alarm_fired")
        #expect(mock.captures[0].properties?["was_app_foreground"] as? Bool == true)
        #expect(mock.captures[0].properties?["hour"] as? Int == 10)
        #expect(mock.captures[0].properties?["detection"] as? String == "observer")
    }

    @Test
    func captureForwardsAlarmStoppedWithSeconds() {
        let mock = MockBackend()
        let service = AnalyticsService(backend: mock)

        service.capture(.alarmStopped(hour: 14))

        #expect(mock.captureCount == 1)
        #expect(mock.captures[0].event == "alarm_stopped")
        #expect(mock.captures[0].properties?["hour"] as? Int == 14)
    }

    @Test
    func captureForwardsAlarmStoppedWithoutSeconds() {
        let mock = MockBackend()
        let service = AnalyticsService(backend: mock)

        service.capture(.alarmStopped(hour: 6))

        #expect(mock.captureCount == 1)
        #expect(mock.captures[0].event == "alarm_stopped")
        #expect(mock.captures[0].properties?["hour"] as? Int == 6)
    }

    @Test
    func captureForwardsAlarmSnoozed() {
        let mock = MockBackend()
        let service = AnalyticsService(backend: mock)

        service.capture(.alarmSnoozed(from: "observer"))

        #expect(mock.captureCount == 1)
        #expect(mock.captures[0].event == "alarm_snoozed")
        #expect(mock.captures[0].properties?["from"] as? String == "observer")
    }

    // MARK: bedside events (Phase 4・#68)

    @Test
    func captureForwardsBedsideEntered() {
        let mock = MockBackend()
        let service = AnalyticsService(backend: mock)

        service.capture(.bedsideEntered(layout: "minimal", theme: "amber", hour: 22))

        #expect(mock.captureCount == 1)
        let captured = mock.captures[0]
        #expect(captured.event == "bedside_entered")
        #expect(captured.properties?["layout"] as? String == "minimal")
        #expect(captured.properties?["theme"] as? String == "amber")
        #expect(captured.properties?["hour"] as? Int == 22)
    }

    @Test
    func captureForwardsBedsideExited() {
        let mock = MockBackend()
        let service = AnalyticsService(backend: mock)

        service.capture(.bedsideExited(durationBucket: "over_2h", exitMethod: "long_press"))

        #expect(mock.captureCount == 1)
        let captured = mock.captures[0]
        #expect(captured.event == "bedside_exited")
        #expect(captured.properties?["duration_bucket"] as? String == "over_2h")
        #expect(captured.properties?["exit_method"] as? String == "long_press")
    }

    @Test
    func captureForwardsBedsideSettingChanged() {
        let mock = MockBackend()
        let service = AnalyticsService(backend: mock)

        service.capture(.bedsideSettingChanged(setting: .layout, value: .string("flip_clock")))

        #expect(mock.captureCount == 1)
        let captured = mock.captures[0]
        #expect(captured.event == "bedside_setting_changed")
        #expect(captured.properties?["setting"] as? String == "layout")
        #expect(captured.properties?["value"] as? String == "flip_clock")
    }

    // MARK: setUserProperties

    @Test
    func setUserPropertiesForwardsToBackend() {
        let mock = MockBackend()
        let service = AnalyticsService(backend: mock)

        service.setUserProperties(["alarm_count": 5, "custom_sound_count": 2])

        #expect(mock.userProperties["alarm_count"] as? Int == 5)
        #expect(mock.userProperties["custom_sound_count"] as? Int == 2)
        #expect(mock.userProperties.count == 2)
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

// MARK: - AnalyticsGateTests

struct AnalyticsGateTests {

    @Test
    func resolve_release_sendsAndNotInternal() {
        let gate = AnalyticsGate.resolve(isDebugBuild: false, debugOptIn: false)
        #expect(gate.shouldSend == true)
        #expect(gate.isInternal == false)
    }

    @Test
    func resolve_release_sendsEvenIfOptInTrue() {
        // opt-in フラグは Release では無視される
        let gate = AnalyticsGate.resolve(isDebugBuild: false, debugOptIn: true)
        #expect(gate.shouldSend == true)
        #expect(gate.isInternal == false)
    }

    @Test
    func resolve_debugNoOptIn_doesNotSend() {
        let gate = AnalyticsGate.resolve(isDebugBuild: true, debugOptIn: false)
        #expect(gate.shouldSend == false)
        #expect(gate.isInternal == true)
    }

    @Test
    func resolve_debugWithOptIn_sendsAsInternal() {
        let gate = AnalyticsGate.resolve(isDebugBuild: true, debugOptIn: true)
        #expect(gate.shouldSend == true)
        #expect(gate.isInternal == true)
    }
}

// MARK: - AnalyticsThrottleTests（#91-2: 診断イベントの送信抑制）

struct AnalyticsThrottleTests {

    // MARK: - review_request_blocked（1セッション1回まで）

    @Test
    func reviewBlocked_firstInSession_sends() {
        #expect(AnalyticsThrottle.shouldSendReviewBlocked(sessionSentCount: 0) == true)
    }

    @Test
    func reviewBlocked_alreadySentInSession_suppressed() {
        // 同一セッションの2回目以降は送らない（scenePhase active のたびの連続送信を抑制）
        #expect(AnalyticsThrottle.shouldSendReviewBlocked(sessionSentCount: 1) == false)
        #expect(AnalyticsThrottle.shouldSendReviewBlocked(sessionSentCount: 5) == false)
    }

    // MARK: - alarm_permission（状態変化時のみ）

    @Test
    func permissionStatus_firstEver_sends() {
        #expect(AnalyticsThrottle.shouldSendPermissionStatus(current: .authorized, lastSent: nil) == true)
        #expect(AnalyticsThrottle.shouldSendPermissionStatus(current: .notDetermined, lastSent: nil) == true)
    }

    @Test
    func permissionStatus_sameAsLastSent_suppressed() {
        // 前回送信時と状態が同じなら送らない（セッションをまたいだ永続比較）
        #expect(AnalyticsThrottle.shouldSendPermissionStatus(current: .authorized, lastSent: .authorized) == false)
        #expect(AnalyticsThrottle.shouldSendPermissionStatus(current: .denied, lastSent: .denied) == false)
        #expect(AnalyticsThrottle.shouldSendPermissionStatus(current: nil, lastSent: nil) == false)
    }

    @Test
    func permissionStatus_changed_sends() {
        #expect(AnalyticsThrottle.shouldSendPermissionStatus(current: .denied, lastSent: .authorized) == true)
        #expect(AnalyticsThrottle.shouldSendPermissionStatus(current: .authorized, lastSent: .notDetermined) == true)
        #expect(AnalyticsThrottle.shouldSendPermissionStatus(current: nil, lastSent: .authorized) == true)
    }
}
