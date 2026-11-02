import Testing
import Foundation
@testable import CustomSoundAlarm

/// 「今すぐ鳴らす」の理由表示の純ロジック（状態→表示文言・ボタンの有無・#150）。
struct TestRingReasonLogicTests {

    @Test
    func permissionReason_mapping() {
        #expect(TestRingReasonLogic.permissionReason(permission: .allowed) == nil)
        #expect(TestRingReasonLogic.permissionReason(permission: .unknown) == .notAuthorized)
        #expect(TestRingReasonLogic.permissionReason(permission: .denied) == .denied)
    }

    @Test
    func reasonRawValues_areStableAnalyticsIdentifiers() {
        // test_ring_failed の reason にそのまま送る。変更で過去データが壊れないこと
        #expect(TestRingFailureReason.notAuthorized.rawValue == "not_authorized")
        #expect(TestRingFailureReason.denied.rawValue == "denied")
        #expect(TestRingFailureReason.scheduleError.rawValue == "schedule_error")
        #expect(TestRingFailureReason.simulator.rawValue == "simulator")
    }

    @Test
    func display_permissionReasonsOfferSettings() {
        let notAuthorized = TestRingReasonLogic.display(for: .notAuthorized)
        #expect(notAuthorized.messageKey == "test_ring_reason_not_authorized")
        #expect(!notAuthorized.showsOpenSettings, "許可がまだなら設定へ送らない（設定に項目がまだ無い）")
        #expect(notAuthorized.requestsPermission, "許可がまだならその場で許可を求める")

        let denied = TestRingReasonLogic.display(for: .denied)
        #expect(denied.messageKey == "test_ring_reason_denied")
        #expect(denied.showsOpenSettings, "拒否済みなら『設定を開く』を出す")
        #expect(!denied.requestsPermission, "拒否済みはダイアログが出ないので設定へ送る")
    }

    @Test
    func display_otherFailuresHaveNoSettingsLink() {
        let scheduleError = TestRingReasonLogic.display(for: .scheduleError)
        #expect(scheduleError.messageKey == "test_ring_failed")
        #expect(!scheduleError.showsOpenSettings, "登録失敗に『設定を開く』は出さない")

        let simulator = TestRingReasonLogic.display(for: .simulator)
        #expect(simulator.messageKey == "test_ring_simulator_unavailable")
        #expect(!simulator.showsOpenSettings, "シミュレータに『設定を開く』は出さない")
    }

    @Test
    func messageKeysExistInBothLanguages() throws {
        let keys = [
            "test_ring_reason_not_authorized",
            "test_ring_reason_denied",
            "test_ring_failed",
            "test_ring_simulator_unavailable",
            "open_settings"
        ]
        for language in ["en", "ja"] {
            let path = try #require(
                Bundle.main.path(
                    forResource: "Localizable",
                    ofType: "strings",
                    inDirectory: nil,
                    forLocalization: language
                )
            )
            let strings = try #require(NSDictionary(contentsOfFile: path) as? [String: String])
            for key in keys {
                #expect(!(strings[key] ?? "").isEmpty, "\(language) \(key)")
            }
        }
    }
}
