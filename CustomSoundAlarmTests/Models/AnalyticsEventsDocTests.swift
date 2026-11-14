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
        "alarm_orphan_cancelled",
        "test_ring_scheduled",
        "test_ring_stopped",
        "test_ring_failed",
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
        "alarm_skip_set",
        "alarm_skip_undone",
        "skip_all_set",
        "skip_all_undone",
        "holiday_skip_toggled",
        "holiday_ring_override",
        "custom_sound_imported",
        "video_import_started",
        "video_import_failed",
        "sound_picker_recent_used",
        "bedside_entered",
        "settings_opened",
        "support_contact_opened",
        "review_link_opened",
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
    func soundPreviewSourcesAreDocumented() throws {
        let doc = try String(contentsOf: docURL, encoding: .utf8)
        let row = try #require(
            doc.split(separator: "\n").first { $0.hasPrefix("| `sound_preview_played` |") }
        )
        for source in SoundPreviewSource.allCases {
            #expect(
                row.contains(source.rawValue),
                "docs/analytics-events.md の sound_preview_played に \(source.rawValue) がありません"
            )
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
