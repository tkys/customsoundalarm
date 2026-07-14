import Testing
import Foundation
@testable import CustomSoundAlarm

/// ReviewRequestManager の「発火実績ベースの依頼可否ロジック」を StoreKit 非依存で検証する。
/// 実際の OS レビュー要求はクロージャ注入なので、ここでは呼ばれた回数だけを観測する。
@MainActor
struct ReviewRequestManagerTests {

    /// テストごとに独立した UserDefaults スイートを用意する。
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "test.review.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    /// 日境界のブレを避けるため固定タイムゾーンの暦を使う。
    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    // MARK: - 発火記録（日単位の冪等性）

    @Test
    func recordAlarmFired_countsOncePerDay() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let sut = ReviewRequestManager(defaults: defaults)
        let cal = utcCalendar
        let day = Date(timeIntervalSince1970: 1_000_000)

        sut.recordAlarmFired(now: day, calendar: cal)
        sut.recordAlarmFired(now: day.addingTimeInterval(3600), calendar: cal) // 同じ日

        #expect(sut.firedDayCount == 1)
    }

    @Test
    func recordAlarmFired_incrementsOnNewDay() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let sut = ReviewRequestManager(defaults: defaults)
        let cal = utcCalendar
        let day = Date(timeIntervalSince1970: 1_000_000)

        sut.recordAlarmFired(now: day, calendar: cal)
        sut.recordAlarmFired(now: day.addingTimeInterval(86_400), calendar: cal)      // 翌日
        sut.recordAlarmFired(now: day.addingTimeInterval(2 * 86_400), calendar: cal)  // 翌々日

        #expect(sut.firedDayCount == 3)
    }

    // MARK: - shouldRequestReview（永続状態のみの純粋判定）

    @Test
    func shouldRequestReview_falseBelowThreshold() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        seedFiredDays(2, defaults: defaults, calendar: utcCalendar)

        // 新しいセッション（発火実績は永続化済み）
        let sut = ReviewRequestManager(defaults: defaults)
        #expect(sut.firedDayCount == 2)
        #expect(sut.shouldRequestReview(appVersion: "1.0") == false)
    }

    @Test
    func shouldRequestReview_trueAtThresholdForNewVersion() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        seedFiredDays(ReviewRequestManager.firedDayThreshold, defaults: defaults, calendar: utcCalendar)

        let sut = ReviewRequestManager(defaults: defaults)
        #expect(sut.shouldRequestReview(appVersion: "1.0") == true)
    }

    @Test
    func shouldRequestReview_falseAfterRequestedSameVersion_trueForNextVersion() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        seedFiredDays(ReviewRequestManager.firedDayThreshold, defaults: defaults, calendar: utcCalendar)

        let sut = ReviewRequestManager(defaults: defaults)
        sut.markRequested(appVersion: "1.0")

        #expect(sut.shouldRequestReview(appVersion: "1.0") == false) // 同一バージョンは再依頼しない
        #expect(sut.shouldRequestReview(appVersion: "1.1") == true)  // 次バージョンは可
    }

    // MARK: - requestReviewIfAppropriate（セッションガード込み）

    @Test
    func requestReviewIfAppropriate_performsAndMarks_whenEligible() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        seedFiredDays(ReviewRequestManager.firedDayThreshold, defaults: defaults, calendar: utcCalendar)

        // 発火が無い落ち着いたセッション（新規インスタンス）
        let sut = ReviewRequestManager(defaults: defaults)
        var performed = 0

        let didRequest = sut.requestReviewIfAppropriate(appVersion: "1.0") { performed += 1 }
        #expect(didRequest == true)
        #expect(performed == 1)

        // 同一バージョンでの2回目は出さない
        let again = sut.requestReviewIfAppropriate(appVersion: "1.0") { performed += 1 }
        #expect(again == false)
        #expect(performed == 1)
    }

    @Test
    func requestReviewIfAppropriate_skips_whenAlarmFiredThisSession() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let cal = utcCalendar
        let sut = ReviewRequestManager(defaults: defaults)
        let day = Date(timeIntervalSince1970: 1_000_000)

        // 同一セッションで閾値まで発火（＝鳴動直後の眠い瞬間を模擬）
        sut.recordAlarmFired(now: day, calendar: cal)
        sut.recordAlarmFired(now: day.addingTimeInterval(86_400), calendar: cal)
        sut.recordAlarmFired(now: day.addingTimeInterval(2 * 86_400), calendar: cal)
        #expect(sut.firedDayCount == ReviewRequestManager.firedDayThreshold)

        var performed = 0
        let didRequest = sut.requestReviewIfAppropriate(appVersion: "1.0") { performed += 1 }

        #expect(didRequest == false) // このセッションで発火しているので出さない
        #expect(performed == 0)
    }

    // MARK: - Helpers

    /// 別セッション（別インスタンス）での発火実績を永続化しておく。
    private func seedFiredDays(_ days: Int, defaults: UserDefaults, calendar: Calendar) {
        let seeder = ReviewRequestManager(defaults: defaults)
        let base = Date(timeIntervalSince1970: 1_000_000)
        for i in 0..<days {
            seeder.recordAlarmFired(now: base.addingTimeInterval(Double(i) * 86_400), calendar: calendar)
        }
    }
}
