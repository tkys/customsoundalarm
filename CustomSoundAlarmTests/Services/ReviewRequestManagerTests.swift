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

    // MARK: - requestReviewIfAppropriate（発火からの経過時間ガード込み・#84）

    @Test
    func requestReviewIfAppropriate_performsAndMarks_whenEligible() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        seedFiredDays(ReviewRequestManager.firedDayThreshold, defaults: defaults, calendar: utcCalendar)

        // 発火から十分時間が経った落ち着いた状態
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

    /// #84 の本体: 発火から4時間以内は出ない
    @Test
    func requestReviewIfAppropriate_suppressedWithin4HoursAfterFire() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        seedFiredDays(ReviewRequestManager.firedDayThreshold, defaults: defaults, calendar: utcCalendar)

        let sut = ReviewRequestManager(defaults: defaults)
        // 閾値達成済みの状態で直近に発火があった
        let fireTime = Date(timeIntervalSince1970: 2_000_000)
        sut.recordAlarmFired(now: fireTime, calendar: utcCalendar)
        #expect(sut.firedDayCount >= ReviewRequestManager.firedDayThreshold)

        var performed = 0
        let didRequest = sut.requestReviewIfAppropriate(appVersion: "1.0", now: fireTime.addingTimeInterval(3 * 3600)) {
            performed += 1
        }

        #expect(didRequest == false) // 発火から3時間 → 出さない
        #expect(performed == 0)
    }

    /// #84 の本体: 4時間経過後は出る。**同一インスタンス（＝プロセスが生き続けている状態）で
    /// 複数回呼んでも、時間条件を満たせば出る**。旧実装はここで永久にブロックされていた
    @Test
    func requestReviewIfAppropriate_allowsAfter4Hours_sameInstance() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        seedFiredDays(ReviewRequestManager.firedDayThreshold, defaults: defaults, calendar: utcCalendar)

        let sut = ReviewRequestManager(defaults: defaults)
        let fireTime = Date(timeIntervalSince1970: 2_000_000)
        sut.recordAlarmFired(now: fireTime, calendar: utcCalendar)

        var performed = 0
        // 同一インスタンスでの1回目: 発火直後 → 出ない
        let first = sut.requestReviewIfAppropriate(appVersion: "1.0", now: fireTime.addingTimeInterval(3600)) {
            performed += 1
        }
        #expect(first == false)

        // 同一インスタンスでの2回目: 4時間経過 → 出る
        let second = sut.requestReviewIfAppropriate(appVersion: "1.0", now: fireTime.addingTimeInterval(4 * 3600)) {
            performed += 1
        }
        #expect(second == true)
        #expect(performed == 1)

        // 同一インスタンスでの3回目: 同一バージョン依頼済み → 出ない
        let third = sut.requestReviewIfAppropriate(appVersion: "1.0", now: fireTime.addingTimeInterval(5 * 3600)) {
            performed += 1
        }
        #expect(third == false)
        #expect(performed == 1)
    }

    /// 同日の再発火（スヌーズ等）でも最終発火時刻は更新され、抑制期間が延長される
    @Test
    func recordAlarmFired_updatesLastFiredAtOnSameDayRefire() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let cal = utcCalendar
        let base = Date(timeIntervalSince1970: 1_000_000)

        // 3日間の発火実績（最終発火は3日目）
        seedFiredDays(ReviewRequestManager.firedDayThreshold, defaults: defaults, calendar: cal)
        let lastSeedDay = base.addingTimeInterval(Double(ReviewRequestManager.firedDayThreshold - 1) * 86_400)

        let sut = ReviewRequestManager(defaults: defaults)
        // 3日目と同じ日の3時間後に再発火（スヌーズ想定・日数は加算されない）
        let refire = lastSeedDay.addingTimeInterval(3 * 3600)
        sut.recordAlarmFired(now: refire, calendar: cal)

        #expect(sut.firedDayCount == ReviewRequestManager.firedDayThreshold)

        // 判定時刻は再発火から3.5時間後（= 3日目の初回発火からは6.5時間後）。
        // 初回発火基準なら出る時間帯だが、再発火が lastFiredAt を更新しているので出ない
        var performed = 0
        let didRequest = sut.requestReviewIfAppropriate(
            appVersion: "1.0",
            now: refire.addingTimeInterval(3.5 * 3600)
        ) { performed += 1 }
        #expect(didRequest == false)
        #expect(performed == 0)
    }

    // MARK: - isPastPostFireInterval（純粋関数・#84）

    @Test
    func isPastPostFireInterval_noFireRecord_allows() {
        #expect(ReviewRequestManager.isPastPostFireInterval(lastFiredAt: nil, now: Date()) == true)
    }

    @Test
    func isPastPostFireInterval_within4Hours_suppresses() {
        let fire = Date(timeIntervalSince1970: 1_000_000)
        // 4時間未満は全て抑制
        #expect(ReviewRequestManager.isPastPostFireInterval(lastFiredAt: fire, now: fire.addingTimeInterval(1)) == false)
        #expect(ReviewRequestManager.isPastPostFireInterval(lastFiredAt: fire, now: fire.addingTimeInterval(3 * 3600 + 59 * 60)) == false)
        // 境界の1秒手前
        #expect(ReviewRequestManager.isPastPostFireInterval(lastFiredAt: fire, now: fire.addingTimeInterval(4 * 3600 - 1)) == false)
    }

    @Test
    func isPastPostFireInterval_after4Hours_allows() {
        let fire = Date(timeIntervalSince1970: 1_000_000)
        // 境界ちょうど（4時間）とそれ以降は許可
        #expect(ReviewRequestManager.isPastPostFireInterval(lastFiredAt: fire, now: fire.addingTimeInterval(4 * 3600)) == true)
        #expect(ReviewRequestManager.isPastPostFireInterval(lastFiredAt: fire, now: fire.addingTimeInterval(24 * 3600)) == true)
    }

    @Test
    func isPastPostFireInterval_clockSkewedBeforeFire_suppresses() {
        // 判定時刻が発火時刻より前（時計巻き戻し等）は負の間隔 → 抑制側に倒す
        let fire = Date(timeIntervalSince1970: 1_000_000)
        #expect(ReviewRequestManager.isPastPostFireInterval(lastFiredAt: fire, now: fire.addingTimeInterval(-1)) == false)
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
