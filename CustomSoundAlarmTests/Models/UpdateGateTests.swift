import Testing
import Foundation
@testable import CustomSoundAlarm

struct UpdateGateTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    private func input(
        current: Int?,
        minimum: Int = 10,
        latest: Int = 12,
        fetchedAt: Date? = nil,
        dismissed: Int? = nil,
        onboarding: Bool = false,
        ringing: Bool = false,
        testRinging: Bool = false
    ) -> UpdateGateInput {
        UpdateGateInput(
            currentBuild: current,
            config: AppConfig(minimumBuild: minimum, latestBuild: latest),
            configFetchedAt: fetchedAt ?? now,
            now: now,
            dismissedRecommendedBuild: dismissed,
            isOnboardingVisible: onboarding,
            isAlarmRinging: ringing,
            isTestRinging: testRinging
        )
    }

    // MARK: - 境界

    @Test
    func belowMinimum_isRequired() {
        let prompt = UpdateGate.decide(input(current: 9))
        #expect(prompt?.kind == .required)
        #expect(prompt?.currentBuild == 9)
        #expect(prompt?.targetBuild == 10)
    }

    @Test
    func atMinimum_isRecommended() {
        let prompt = UpdateGate.decide(input(current: 10))
        #expect(prompt?.kind == .recommended)
        #expect(prompt?.targetBuild == 12)
    }

    @Test
    func justBelowLatest_isRecommended() {
        #expect(UpdateGate.decide(input(current: 11))?.kind == .recommended)
    }

    @Test
    func atLatest_isNone() {
        #expect(UpdateGate.decide(input(current: 12)) == nil)
    }

    @Test
    func aboveLatest_isNone() {
        #expect(UpdateGate.decide(input(current: 13)) == nil)
    }

    @Test
    func minimumEqualsLatest() {
        #expect(UpdateGate.decide(input(current: 9, minimum: 10, latest: 10))?.kind == .required)
        #expect(UpdateGate.decide(input(current: 10, minimum: 10, latest: 10)) == nil)
    }

    // MARK: - 取得失敗・解析失敗

    @Test
    func missingConfig_doesNothing() {
        let input = UpdateGateInput(
            currentBuild: 9,
            config: nil,
            configFetchedAt: nil,
            now: now,
            dismissedRecommendedBuild: nil,
            isOnboardingVisible: false,
            isAlarmRinging: false,
            isTestRinging: false
        )
        #expect(UpdateGate.decide(input) == nil)
    }

    @Test
    func unreadableCurrentBuild_doesNothing() {
        #expect(UpdateGate.decide(input(current: nil)) == nil)
    }

    @Test
    func invalidJSON_isRejected() {
        #expect(AppConfig(data: Data("{}".utf8)) == nil)
        #expect(AppConfig(data: Data(#"{"minimum_build": 1}"#.utf8)) == nil)
        #expect(AppConfig(data: Data(#"{"minimum_build": "1", "latest_build": 10}"#.utf8)) == nil)
        #expect(AppConfig(data: Data(#"{"minimum_build": -1, "latest_build": 10}"#.utf8)) == nil)
        #expect(AppConfig(data: Data(#"{"minimum_build": 11, "latest_build": 10}"#.utf8)) == nil)
        #expect(AppConfig(data: Data("not json".utf8)) == nil)
    }

    @Test
    func validJSON_isDecoded() {
        let config = AppConfig(data: Data(#"{"minimum_build": 0, "latest_build": 10}"#.utf8))
        #expect(config == AppConfig(minimumBuild: 0, latestBuild: 10))
    }

    // MARK: - キャッシュの鮮度

    @Test
    func requiredFromStaleCache_isIgnored() {
        let stale = now.addingTimeInterval(-8 * day)
        #expect(UpdateGate.decide(input(current: 9, fetchedAt: stale)) == nil)
    }

    @Test
    func requiredFromRecentCache_isShown() {
        let recent = now.addingTimeInterval(-6 * day)
        #expect(UpdateGate.decide(input(current: 9, fetchedAt: recent))?.kind == .required)
    }

    @Test
    func requiredWithoutFetchedAt_isIgnored() {
        let input = UpdateGateInput(
            currentBuild: 9,
            config: AppConfig(minimumBuild: 10, latestBuild: 12),
            configFetchedAt: nil,
            now: now,
            dismissedRecommendedBuild: nil,
            isOnboardingVisible: false,
            isAlarmRinging: false,
            isTestRinging: false
        )
        #expect(UpdateGate.decide(input) == nil)
    }

    @Test
    func recommendedFromStaleCache_isStillShown() {
        // 「必須」だけが7日制限。おすすめは古いキャッシュでも出してよい
        let stale = now.addingTimeInterval(-30 * day)
        #expect(UpdateGate.decide(input(current: 10, fetchedAt: stale))?.kind == .recommended)
    }

    // MARK: - おすすめは latest_build ごとに1回

    @Test
    func recommended_isSuppressedAfterDismiss() {
        #expect(UpdateGate.decide(input(current: 10, dismissed: 12)) == nil)
    }

    @Test
    func recommended_showsAgainWhenLatestIncreases() {
        #expect(UpdateGate.decide(input(current: 10, latest: 13, dismissed: 12))?.kind == .recommended)
    }

    @Test
    func required_isNotSuppressedByDismissedRecommended() {
        #expect(UpdateGate.decide(input(current: 9, dismissed: 12))?.kind == .required)
    }

    // MARK: - 出さない場面

    @Test
    func onboarding_blocksPrompt() {
        #expect(UpdateGate.decide(input(current: 9, onboarding: true)) == nil)
        #expect(UpdateGate.decide(input(current: 10, onboarding: true)) == nil)
    }

    @Test
    func alarmRinging_blocksPrompt() {
        #expect(UpdateGate.decide(input(current: 9, ringing: true)) == nil)
        #expect(UpdateGate.decide(input(current: 10, ringing: true)) == nil)
    }

    @Test
    func testRinging_blocksPrompt() {
        #expect(UpdateGate.decide(input(current: 9, testRinging: true)) == nil)
        #expect(UpdateGate.decide(input(current: 10, testRinging: true)) == nil)
    }

    // MARK: - ビルド番号

    @Test
    func currentBuild_isReadableFromBundle() {
        #expect(UpdateGate.currentBuild() != nil)
    }

    // MARK: - App Group

    @Test
    func cacheAndDismissal_roundTrip() {
        let originalData = AppGroup.cachedAppConfigData
        let originalFetched = AppGroup.cachedAppConfigFetchedAt
        let originalDismissed = AppGroup.dismissedRecommendedBuild
        defer {
            AppGroup.cachedAppConfigData = originalData
            AppGroup.cachedAppConfigFetchedAt = originalFetched
            AppGroup.dismissedRecommendedBuild = originalDismissed
        }

        let data = try? JSONEncoder().encode(AppConfig(minimumBuild: 0, latestBuild: 10))
        AppGroup.cachedAppConfigData = data
        AppGroup.cachedAppConfigFetchedAt = now
        AppGroup.dismissedRecommendedBuild = 10

        #expect(AppConfig(data: AppGroup.cachedAppConfigData!) == AppConfig(minimumBuild: 0, latestBuild: 10))
        #expect(AppGroup.cachedAppConfigFetchedAt == now)
        #expect(AppGroup.dismissedRecommendedBuild == 10)

        AppGroup.dismissedRecommendedBuild = nil
        #expect(AppGroup.dismissedRecommendedBuild == nil)
    }
}
