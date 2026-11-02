import Foundation
import Testing
@testable import CustomSoundAlarm

// MARK: - Test support

/// `AdPolicy` の実判定から `AdDecision` を作る。
/// ゲート／コーディネータのテストを、手作りの `AdDecision` ではなく
/// 実際の既存ユーザー・PRO 判定に結び付ける。
private enum AdSDKTestSupport {
    static let utc = TimeZone(identifier: "UTC")!

    static func decision(
        originalAppVersion: String? = String(AdsConfig.introductionBuild),
        isPro: Bool = false
    ) -> AdDecision {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        var components = DateComponents()
        components.year = 2024; components.month = 1; components.day = 15
        components.hour = 12; components.minute = 0; components.second = 0
        let now = calendar.date(from: components)!

        let input = AdPolicyInput(
            now: now,
            timeZone: utc,
            firstLaunchDate: now.addingTimeInterval(-30 * 24 * 60 * 60),
            originalAppVersion: originalAppVersion,
            introductionBuild: AdsConfig.introductionBuild,
            isPro: isPro,
            lastInterstitialShownAt: nil,
            region: .standard
        )
        return AdPolicy(input: input).canShowBanner(context: .soundsList)
    }
}

// MARK: - AdSDKGate

struct AdSDKGateTests {

    private func decision(
        allowed: Bool,
        reason: AdDecisionReason,
        region: AdRegion = .standard
    ) -> AdDecision {
        AdDecision(allowed: allowed, reason: reason, region: region)
    }

    @Test
    func initializesOnlyWhenEnabledAndEligible() {
        let eligible = decision(allowed: true, reason: .eligible)
        #expect(AdSDKGate.mayInitialize(isEnabled: true, decision: eligible))
        #expect(!AdSDKGate.mayInitialize(isEnabled: false, decision: eligible))
    }

    @Test
    func existingUser_neverInitializes() {
        let existing = AdSDKTestSupport.decision(originalAppVersion: "11")
        #expect(existing.reason == .existingUser)
        #expect(!AdSDKGate.mayInitialize(isEnabled: true, decision: existing))
    }

    @Test
    func pro_neverInitializes() {
        let pro = AdSDKTestSupport.decision(isPro: true)
        #expect(pro.reason == .pro)
        #expect(!AdSDKGate.mayInitialize(isEnabled: true, decision: pro))
    }

    @Test
    func firstWeekAndQuietHours_doNotInitializeUntilEligible() {
        #expect(!AdSDKGate.mayInitialize(
            isEnabled: true,
            decision: decision(allowed: false, reason: .firstWeek)
        ))
        #expect(!AdSDKGate.mayInitialize(
            isEnabled: true,
            decision: decision(allowed: false, reason: .quietHours)
        ))
    }
}

// MARK: - AdSDKPrivacy

struct AdSDKPrivacyTests {

    @Test
    func limitedOnlyRegionsUseLimitedAdsWithoutConsentForm() {
        for code in ["FR", "DE", "GB", "CH", "NO", "IS", "LI"] {
            let privacy = AdSDKPrivacy.resolve(
                region: AdRegionLogic.region(forCountryCode: code)
            )
            #expect(privacy.region == .limitedOnly, "\(code)")
            #expect(privacy.limitedAds, "\(code) must use limited ads")
            #expect(!privacy.presentsConsentForm, "\(code) must not present a consent form")
            #expect(privacy.personalizationDisabled, "\(code)")
        }
    }

    @Test
    func standardRegionsStayNonPersonalizedWithoutConsentForm() {
        let privacy = AdSDKPrivacy.resolve(region: .standard)
        #expect(privacy.region == .standard)
        #expect(!privacy.limitedAds)
        #expect(!privacy.presentsConsentForm)
        #expect(privacy.personalizationDisabled)
    }

    @Test
    func applierWritesLimitedAdsKeyOnlyForRestrictedRegions() {
        let suiteName = "AdSDKPrivacyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = AdSDKPrivacyApplier.limitedAdsConsentKey

        AdSDKPrivacyApplier.apply(.resolve(region: .limitedOnly), defaults: defaults)
        #expect(defaults.object(forKey: key) as? Int == 0)

        AdSDKPrivacyApplier.apply(.resolve(region: .standard), defaults: defaults)
        #expect(defaults.object(forKey: key) == nil)
    }
}

// MARK: - AdSDKCoordinator

@MainActor
private final class FakeADSInitializer: AdSDKInitializing {
    private(set) var calls: [AdSDKPrivacy] = []

    func start(privacy: AdSDKPrivacy) async {
        calls.append(privacy)
    }
}

@MainActor
struct AdSDKCoordinatorTests {

    private func decision(
        allowed: Bool,
        reason: AdDecisionReason,
        region: AdRegion = .standard
    ) -> AdDecision {
        AdDecision(allowed: allowed, reason: reason, region: region)
    }

    @Test
    func existingUser_doesNotStartSDK() async {
        let initializer = FakeADSInitializer()
        let coordinator = AdSDKCoordinator(initializer: initializer)

        await coordinator.prepare(
            isEnabled: true,
            decision: AdSDKTestSupport.decision(originalAppVersion: "11")
        )

        #expect(initializer.calls.isEmpty)
        #expect(!coordinator.isInitialized)
    }

    @Test
    func pro_doesNotStartSDK() async {
        let initializer = FakeADSInitializer()
        let coordinator = AdSDKCoordinator(initializer: initializer)

        await coordinator.prepare(
            isEnabled: true,
            decision: AdSDKTestSupport.decision(isPro: true)
        )

        #expect(initializer.calls.isEmpty)
        #expect(!coordinator.isInitialized)
    }

    @Test
    func disabledConfig_doesNotStartSDK() async {
        let initializer = FakeADSInitializer()
        let coordinator = AdSDKCoordinator(initializer: initializer)

        await coordinator.prepare(
            isEnabled: false,
            decision: decision(allowed: true, reason: .eligible)
        )

        #expect(initializer.calls.isEmpty)
        #expect(!coordinator.isInitialized)
    }

    @Test
    func eligibleUser_startsOnceWithLimitedPrivacy() async {
        let initializer = FakeADSInitializer()
        let coordinator = AdSDKCoordinator(initializer: initializer)
        let limited = decision(allowed: true, reason: .eligible, region: .limitedOnly)

        await coordinator.prepare(isEnabled: true, decision: limited)
        await coordinator.prepare(isEnabled: true, decision: limited)

        #expect(initializer.calls.count == 1)
        #expect(initializer.calls.first?.limitedAds == true)
        #expect(initializer.calls.first?.presentsConsentForm == false)
        #expect(coordinator.isInitialized)
    }
}

// MARK: - AdInterstitialCache

struct AdInterstitialCacheTests {
    private let loadedAt = Date(timeIntervalSince1970: 1_000_000)

    @Test
    func freshImmediatelyAfterLoad() {
        #expect(AdInterstitialCache.isFresh(loadedAt: loadedAt, now: loadedAt))
    }

    @Test
    func freshAt54Minutes59Seconds() {
        let now = loadedAt.addingTimeInterval(54 * 60 + 59)
        #expect(AdInterstitialCache.isFresh(loadedAt: loadedAt, now: now))
    }

    @Test
    func staleAt55Minutes() {
        let now = loadedAt.addingTimeInterval(55 * 60)
        #expect(!AdInterstitialCache.isFresh(loadedAt: loadedAt, now: now))
    }

    @Test
    func staleAfter55Minutes() {
        let now = loadedAt.addingTimeInterval(55 * 60 + 1)
        #expect(!AdInterstitialCache.isFresh(loadedAt: loadedAt, now: now))
    }

    @Test
    func staleWhenClockMovesBackwards() {
        let now = loadedAt.addingTimeInterval(-1)
        #expect(!AdInterstitialCache.isFresh(loadedAt: loadedAt, now: now))
    }
}

// MARK: - AdFailureCode

struct AdFailureCodeTests {

    @Test
    func mapsGoogleErrorCodesToStableStrings() {
        let cases: [(Int, AdFailureCode)] = [
            (0, .invalidRequest),
            (1, .noFill),
            (2, .networkError),
            (3, .serverError),
            (5, .timeout),
            (11, .internalError),
            (999, .unknown)
        ]
        for (code, expected) in cases {
            let error = NSError(domain: "com.google.admob", code: code)
            #expect(AdFailureCode.from(error) == expected, "\(code)")
        }
    }

    @Test
    func unknownDomainIsUnknown() {
        let error = NSError(domain: "example.com", code: 1)
        #expect(AdFailureCode.from(error) == .unknown)
    }
}
