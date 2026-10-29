import Testing
import Foundation
@testable import CustomSoundAlarm

/// `docs/analytics-events.md` に全イベント名が載っていることを検証する（#124）。
struct AnalyticsEventsDocTests {

    private static let allEventNames = [
        "alarm_created",
        "alarm_edited",
        "alarm_deleted",
        "alarm_duplicated",
        "alarm_permission",
        "alarm_fired",
        "alarm_stopped",
        "alarm_snoozed",
        "test_ring_scheduled",
        "test_ring_stopped",
        "backup_alarm_enabled",
        "backup_alarm_disabled",
        "backup_alarm_fired",
        "backup_alarm_stopped",
        "backup_alarm_cancelled_by_stop",
        "backup_loud_variant_generated",
        "backup_loud_variant_failed",
        "volume_guide_opened",
        "update_prompt_shown",
        "update_prompt_tapped",
        "update_prompt_dismissed",
        "sound_selected",
        "ad_slot_eligible",
        "sound_preview_played",
        "custom_sound_imported",
        "video_import_started",
        "video_import_failed",
        "sound_picker_recent_used",
        "bedside_entered",
        "bedside_exited",
        "bedside_setting_changed",
        "onboarding_step_viewed",
        "onboarding_source_selected",
        "onboarding_completed",
        "review_requested",
        "review_request_blocked"
    ]

    private var docURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Models
            .deletingLastPathComponent() // CustomSoundAlarmTests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("docs/analytics-events.md")
    }

    @Test
    func allEventNamesAreDocumented() throws {
        let doc = try String(contentsOf: docURL, encoding: .utf8)
        for name in Self.allEventNames {
            #expect(doc.contains("| `\(name)` |"), "docs/analytics-events.md の表に `\(name)` がありません")
        }
    }

    @Test
    func userPropertiesAreDocumented() throws {
        let doc = try String(contentsOf: docURL, encoding: .utf8)
        let properties = [
            "custom_sound_count",
            "alarm_count",
            "first_install_version",
            "sound_total_seconds_bucket",
            "sound_max_seconds_bucket",
            "backup_alarm_count",
            "backup_early_access",
            "first_install_build"
        ]
        for name in properties {
            #expect(doc.contains("| `\(name)` |"), "docs/analytics-events.md の表に `\(name)` がありません")
        }
    }
}
