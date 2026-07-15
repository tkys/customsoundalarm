import Testing
import Foundation
@testable import CustomSoundAlarm

/// `AlarmCountdown` の時間計算（純粋関数）を検証する。
/// ローカライズ文字列の出力そのものは言語設定に依存するため、
/// 数値計算（`components` / `hoursUntil`）を中心に検証し、
/// 文字列表現は「空でないこと・負の表現を含まないこと」を軽く確認する。
struct AlarmCountdownTests {

    private func interval(_ seconds: TimeInterval) -> (Date, Date) {
        let ref = Date()
        return (ref, ref.addingTimeInterval(seconds))
    }

    // MARK: - components

    @Test
    func components_thirtyMinutes() {
        let (ref, fire) = interval(30 * 60)
        let c = AlarmCountdown.components(from: ref, to: fire)
        #expect(c == .init(days: 0, hours: 0, minutes: 30))
    }

    @Test
    func components_underOneMinute_isZero() {
        let (ref, fire) = interval(12)
        let c = AlarmCountdown.components(from: ref, to: fire)
        #expect(c == .init(days: 0, hours: 0, minutes: 0))
    }

    @Test
    func components_hoursAndMinutes() {
        // 7時間30分
        let (ref, fire) = interval(7 * 3600 + 30 * 60)
        let c = AlarmCountdown.components(from: ref, to: fire)
        #expect(c == .init(days: 0, hours: 7, minutes: 30))
    }

    @Test
    func components_exactHours() {
        // 7時間ちょうど（分は0）
        let (ref, fire) = interval(7 * 3600)
        let c = AlarmCountdown.components(from: ref, to: fire)
        #expect(c == .init(days: 0, hours: 7, minutes: 0))
    }

    @Test
    func components_daysAndHours() {
        // 2日3時間 = 51時間
        let (ref, fire) = interval(2 * 86400 + 3 * 3600)
        let c = AlarmCountdown.components(from: ref, to: fire)
        #expect(c == .init(days: 2, hours: 3, minutes: 0))
    }

    @Test
    func components_daysHoursMinutes() {
        // 2日3時間15分
        let (ref, fire) = interval(2 * 86400 + 3 * 3600 + 15 * 60)
        let c = AlarmCountdown.components(from: ref, to: fire)
        #expect(c == .init(days: 2, hours: 3, minutes: 15))
    }

    @Test
    func components_fireBeforeReference_clampedToZero() {
        // 発火が過去（負の間隔）→ 全 0（負にならない）
        let (ref, fire) = interval(-3600)
        let c = AlarmCountdown.components(from: ref, to: fire)
        #expect(c == .init(days: 0, hours: 0, minutes: 0))
    }

    // MARK: - hoursUntil

    @Test
    func hoursUntil_underOneHour_isZero() {
        let (ref, fire) = interval(45 * 60)
        #expect(AlarmCountdown.hoursUntil(from: ref, to: fire) == 0)
    }

    @Test
    func hoursUntil_truncatesMinutes() {
        // 7時間59分 → 7（切り捨て）
        let (ref, fire) = interval(7 * 3600 + 59 * 60)
        #expect(AlarmCountdown.hoursUntil(from: ref, to: fire) == 7)
    }

    @Test
    func hoursUntil_exactHours() {
        let (ref, fire) = interval(8 * 3600)
        #expect(AlarmCountdown.hoursUntil(from: ref, to: fire) == 8)
    }

    @Test
    func hoursUntil_multiDayExceeds24() {
        // 2日3時間 = 51時間
        let (ref, fire) = interval(2 * 86400 + 3 * 3600)
        #expect(AlarmCountdown.hoursUntil(from: ref, to: fire) == 51)
    }

    @Test
    func hoursUntil_fireBeforeReference_isZero() {
        let (ref, fire) = interval(-7200)
        #expect(AlarmCountdown.hoursUntil(from: ref, to: fire) == 0)
    }

    // MARK: - 文字列表現（軽い検証）

    @Test
    func durationString_isNonEmptyForMinutes() {
        let (ref, fire) = interval(45 * 60)
        let s = AlarmCountdown.durationString(from: ref, to: fire)
        #expect(!s.isEmpty)
        #expect(s.contains("45"))
    }

    @Test
    func untilString_isNonEmpty() {
        let (ref, fire) = interval(7 * 3600 + 30 * 60)
        let s = AlarmCountdown.untilString(from: ref, to: fire)
        #expect(!s.isEmpty)
        // 負の記号が含まれないこと（PII/異常値でないことの目安）
        #expect(!s.contains("-"))
    }
}
