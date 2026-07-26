import Testing
import Foundation
@testable import CustomSoundAlarm

/// `PostSaveFeedback` の純粋関数（3分岐）を検証する。
/// ローカライズ文字列（`localizedMessage`）はロケール依存のため、
/// resolve のみを検証し `localizedMessage` は nil 可能性のみテストする。
struct PostSaveFeedbackTests {

    // MARK: - resolve: 有効アラーム

    @Test
    func resolve_enabledAlarm_returnsWillRing() {
        let entry = AlarmEntry(
            hour: 7, minute: 0,
            isEnabled: true,
            label: "test",
            repeatWeekdays: [],
            soundFileName: ""
        )
        // 未来の時刻を指定して nextFireDate が取れる状態を作る
        var components = DateComponents()
        components.hour = 6
        components.minute = 0
        let currentDate = Calendar.current.date(from: components) ?? Date()

        let result = PostSaveFeedback.resolve(for: entry, currentDate: currentDate)
        #expect(result == .willRing)
    }

    // MARK: - resolve: 無効アラーム

    @Test
    func resolve_disabledAlarm_returnsIsOff() {
        let entry = AlarmEntry(
            hour: 7, minute: 0,
            isEnabled: false,
            label: "test",
            repeatWeekdays: [],
            soundFileName: ""
        )
        let result = PostSaveFeedback.resolve(for: entry, currentDate: Date())
        #expect(result == .isOff)
    }

    // MARK: - resolve: 有効だが発火日時が算出不能

    @Test
    func resolve_enabledButInvalidTime_returnsSilent() {
        // 不正な時刻（hour=25）だと nextFireDate は nil
        let entry = AlarmEntry(
            hour: 25, minute: 0,
            isEnabled: true,
            label: "invalid",
            repeatWeekdays: [],
            soundFileName: ""
        )
        let result = PostSaveFeedback.resolve(for: entry, currentDate: Date())
        #expect(result == .silent)
    }

    // MARK: - localizedMessage: nil テスト

    @Test
    func localizedMessage_silentCase_returnsNil() {
        let entry = AlarmEntry(
            hour: 25, minute: 0,
            isEnabled: true,
            label: "invalid",
            repeatWeekdays: [],
            soundFileName: ""
        )
        let message = PostSaveFeedback.silent.localizedMessage(entry: entry, currentDate: Date())
        #expect(message == nil)
    }

    @Test
    func localizedMessage_isOffCase_returnsNonNil() {
        let entry = AlarmEntry(
            hour: 7, minute: 0,
            isEnabled: false,
            label: "off",
            repeatWeekdays: [],
            soundFileName: ""
        )
        let message = PostSaveFeedback.isOff.localizedMessage(entry: entry, currentDate: Date())
        #expect(message != nil)
    }

    @Test
    func localizedMessage_willRingCase_returnsNonNilWhenValid() {
        let entry = AlarmEntry(
            hour: 7, minute: 0,
            isEnabled: true,
            label: "on",
            repeatWeekdays: [],
            soundFileName: ""
        )
        var components = DateComponents()
        components.hour = 6
        components.minute = 0
        let currentDate = Calendar.current.date(from: components) ?? Date()

        let message = PostSaveFeedback.willRing.localizedMessage(entry: entry, currentDate: currentDate)
        #expect(message != nil)
    }
}