import Foundation
import Testing
@testable import CustomSoundAlarm

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
        let existing = decision(allowed: false, reason: .existingUser)
        #expect(!AdSDKGate.mayInitialize(isEnabled: true, decision: existing))
    }

    @Test
    func pro_neverInitializes() {
        let pro = decision(allowed: false, reason: .pro)
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
            decision: decision(allowed: false, reason: .existingUser)
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
            decision: decision(allowed: false, reason: .pro)
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
