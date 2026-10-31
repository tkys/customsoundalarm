import Testing
import Foundation
@testable import CustomSoundAlarm

struct AdPolicyTests {

    private static let utc: TimeZone = TimeZone(identifier: "UTC")!
    private static let tokyo: TimeZone = TimeZone(identifier: "Asia/Tokyo")!

    private func date(
        _ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int,
        timeZone: TimeZone = AdPolicyTests.utc
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d
        c.hour = h; c.minute = mi; c.second = 0
        return calendar.date(from: c)!
    }

    private func input(
        now: Date,
        timeZone: TimeZone = AdPolicyTests.utc,
        firstLaunchDate: Date? = nil,
        originalAppVersion: String? = String(AdsConfig.introductionBuild),
        isPro: Bool = false,
        lastInterstitialShownAt: Date? = nil,
        region: AdRegion = .standard
    ) -> AdPolicyInput {
        AdPolicyInput(
            now: now,
            timeZone: timeZone,
            firstLaunchDate: firstLaunchDate ?? now.addingTimeInterval(-30 * 24 * 60 * 60),
            originalAppVersion: originalAppVersion,
            introductionBuild: AdsConfig.introductionBuild,
            isPro: isPro,
            lastInterstitialShownAt: lastInterstitialShownAt,
            region: region
        )
    }

    private func policy(now: Date = AdPolicyTests.utcDate(2024, 1, 15, 12, 0)) -> AdPolicy {
        AdPolicy(input: input(now: now))
    }

    private static func utcDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d
        c.hour = h; c.minute = mi; c.second = 0
        return calendar.date(from: c)!
    }

    // MARK: - 基本

    @Test
    func bannerSounds_eligible() {
        let decision = policy().canShowBanner(context: .soundsList)
        #expect(decision.allowed)
        #expect(decision.reason == .eligible)
        #expect(decision.region == .standard)
    }

    @Test
    func bannerImport_eligible() {
        #expect(policy().canShowBanner(context: .importScreen).allowed)
    }

    @Test
    func interstitialImportSaved_eligible() {
        #expect(policy().canShowInterstitial(context: .importSaved).allowed)
    }

    // MARK: - 既存ユーザー / バージョン

    @Test
    func existingBuilds_areDenied() {
        let now = Self.utcDate(2024, 1, 15, 12, 0)
        // 実値: v1.5.0=6 / v1.7.1=9 / v1.8.0=10 / v1.8.1=11（広告導入は 1.9.0=12）
        for build in ["6", "9", "10", "11"] {
            let p = AdPolicy(input: input(now: now, originalAppVersion: build))
            let decision = p.canShowBanner(context: .soundsList)
            #expect(!decision.allowed, "build \(build) must not see ads")
            #expect(decision.reason == .existingUser, "build \(build)")
        }
    }

    /// 1.8.1（ビルド11）は広告・制限の導入前に出るので、そこで入れた人は既存ユーザー（2026-10-30）
    @Test
    func build181_isExistingUser() {
        #expect(AdsConfig.introductionBuild == 12, "1.9.0 = build 12; 1.8.1 (11) users must stay exempt")
        let p = AdPolicy(input: input(now: Self.utcDate(2024, 1, 15, 12, 0), originalAppVersion: "11"))
        #expect(p.canShowBanner(context: .soundsList).reason == .existingUser)
    }

    @Test
    func introductionBuildAndLater_areAllowed() {
        let now = Self.utcDate(2024, 1, 15, 12, 0)
        for build in [String(AdsConfig.introductionBuild), String(AdsConfig.introductionBuild + 1)] {
            let p = AdPolicy(input: input(now: now, originalAppVersion: build))
            #expect(p.canShowBanner(context: .soundsList).allowed, "build \(build)")
        }
    }

    @Test
    func versionUnavailable_isDenied() {
        let now = Self.utcDate(2024, 1, 15, 12, 0)
        // nil / 空 / マーケティングバージョン形式（"1.0"）は Int に解釈できない
        for value in [nil, "", "1.0", "abc"] as [String?] {
            let p = AdPolicy(input: input(now: now, originalAppVersion: value))
            let decision = p.canShowBanner(context: .soundsList)
            #expect(!decision.allowed)
            #expect(decision.reason == .versionUnavailable, "value \(value ?? "nil")")
        }
    }

    @Test
    func parseBuild_acceptsOnlyIntegerBuildNumbers() {
        #expect(AdPolicy.parseBuild("6") == 6)
        #expect(AdPolicy.parseBuild("11") == 11)
        #expect(AdPolicy.parseBuild(" 12 ") == 12)
        #expect(AdPolicy.parseBuild(nil) == nil)
        #expect(AdPolicy.parseBuild("") == nil)
        #expect(AdPolicy.parseBuild("1.0") == nil)
        #expect(AdPolicy.parseBuild("abc") == nil)
    }

    // MARK: - PRO

    @Test
    func pro_isDenied() {
        let now = Self.utcDate(2024, 1, 15, 12, 0)
        let p = AdPolicy(input: input(now: now, isPro: true))
        let decision = p.canShowBanner(context: .soundsList)
        #expect(!decision.allowed)
        #expect(decision.reason == .pro)
    }

    // MARK: - 初回起動から7日

    @Test
    func firstSixDays_areDenied() {
        let now = Self.utcDate(2024, 1, 15, 12, 0)
        let first = now.addingTimeInterval(-6 * 24 * 60 * 60)
        let p = AdPolicy(input: input(now: now, firstLaunchDate: first))
        let decision = p.canShowBanner(context: .soundsList)
        #expect(!decision.allowed)
        #expect(decision.reason == .firstWeek)
    }

    @Test
    func sevenDays_areAllowed() {
        let now = Self.utcDate(2024, 1, 15, 12, 0)
        let first = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let p = AdPolicy(input: input(now: now, firstLaunchDate: first))
        #expect(p.canShowBanner(context: .soundsList).allowed)
    }

    @Test
    func missingFirstLaunch_isDenied() {
        let now = Self.utcDate(2024, 1, 15, 12, 0)
        let direct = AdPolicy(input: AdPolicyInput(
            now: now,
            timeZone: Self.utc,
            firstLaunchDate: nil,
            originalAppVersion: String(AdsConfig.introductionBuild),
            introductionBuild: AdsConfig.introductionBuild,
            isPro: false,
            lastInterstitialShownAt: nil,
            region: .standard
        ))
        #expect(!direct.canShowBanner(context: .soundsList).allowed)
        #expect(direct.canShowBanner(context: .soundsList).reason == .firstWeek)
    }

    // MARK: - 21:00〜6:59

    @Test
    func quietHours_utc() {
        let at21 = AdPolicy(input: input(now: date(2024, 1, 15, 21, 0)))
        #expect(at21.canShowBanner(context: .soundsList).reason == .quietHours)

        let at659 = AdPolicy(input: input(now: date(2024, 1, 15, 6, 59)))
        #expect(at659.canShowBanner(context: .soundsList).reason == .quietHours)

        let at7 = AdPolicy(input: input(now: date(2024, 1, 15, 7, 0)))
        #expect(at7.canShowBanner(context: .soundsList).allowed)
    }

    @Test
    func quietHours_respectsTimeZone() {
        // 21:00 JST = 12:00 UTC
        let at21JST = AdPolicy(input: input(
            now: date(2024, 1, 15, 21, 0, timeZone: Self.tokyo),
            timeZone: Self.tokyo
        ))
        #expect(at21JST.canShowBanner(context: .soundsList).reason == .quietHours)

        // 07:00 JST = 22:00 UTC（UTC では静かな時間だが、地元時刻で許可）
        let at7JST = AdPolicy(input: input(
            now: date(2024, 1, 15, 7, 0, timeZone: Self.tokyo),
            timeZone: Self.tokyo
        ))
        #expect(at7JST.canShowBanner(context: .soundsList).allowed)

        let at659JST = AdPolicy(input: input(
            now: date(2024, 1, 15, 6, 59, timeZone: Self.tokyo),
            timeZone: Self.tokyo
        ))
        #expect(at659JST.canShowBanner(context: .soundsList).reason == .quietHours)
    }

    // MARK: - 全画面は週1回

    @Test
    func interstitial_sixDaysAfter_isDenied() {
        let now = Self.utcDate(2024, 1, 15, 12, 0)
        let last = now.addingTimeInterval(-6 * 24 * 60 * 60)
        let p = AdPolicy(input: input(now: now, lastInterstitialShownAt: last))
        let decision = p.canShowInterstitial(context: .importSaved)
        #expect(!decision.allowed)
        #expect(decision.reason == .frequencyCap)
    }

    @Test
    func interstitial_sevenDaysAfter_isAllowed() {
        let now = Self.utcDate(2024, 1, 15, 12, 0)
        let last = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let p = AdPolicy(input: input(now: now, lastInterstitialShownAt: last))
        #expect(p.canShowInterstitial(context: .importSaved).allowed)
    }

    @Test
    func banner_isNotAffectedByInterstitialFrequency() {
        let now = Self.utcDate(2024, 1, 15, 12, 0)
        let last = now.addingTimeInterval(-1 * 24 * 60 * 60)
        let p = AdPolicy(input: input(now: now, lastInterstitialShownAt: last))
        #expect(p.canShowBanner(context: .soundsList).allowed)
    }

    // MARK: - 禁止画面 / 種類違い

    @Test
    func forbiddenContexts_areDenied() {
        // 仕様変更（2026-10-30）: アラーム一覧は下部バナーの対象になったため、
        // 禁止画面のリストから外した。昼の可否は bannerAlarmList_* で検証する。
        let contexts: [AdContext] = [.bedside, .onboarding, .alarmRinging, .testRinging]
        for context in contexts {
            let banner = policy().canShowBanner(context: context)
            #expect(!banner.allowed)
            #expect(banner.reason == .forbiddenContext)
            #expect(policy().canShowInterstitial(context: context).reason == .forbiddenContext)
        }
    }

    @Test
    func wrongContext_isDenied() {
        let banner = policy().canShowBanner(context: .importSaved)
        #expect(banner.reason == .wrongContext)

        let interstitial = policy().canShowInterstitial(context: .soundsList)
        #expect(interstitial.reason == .wrongContext)
    }

    // MARK: - 地域

    @Test
    func region_limitedForEEAUKAndSwitzerland() {
        for code in ["FR", "DE", "GB", "CH", "NO", "IS", "LI", "SE"] {
            #expect(AdRegionLogic.region(forCountryCode: code) == .limitedOnly, "\(code)")
        }
    }

    @Test
    func region_standardForUSAndJapan() {
        #expect(AdRegionLogic.region(forCountryCode: "US") == .standard)
        #expect(AdRegionLogic.region(forCountryCode: "JP") == .standard)
        #expect(AdRegionLogic.region(forCountryCode: "us") == .standard)
    }

    @Test
    func region_nilFallsBackToLimited() {
        #expect(AdRegionLogic.region(forCountryCode: nil) == .limitedOnly)
        #expect(AdRegionLogic.region(forCountryCode: "") == .limitedOnly)
        #expect(AdRegionLogic.region(forCountryCode: "   ") == .limitedOnly)
    }

    @Test
    func region_storefrontPreferredThenDeviceThenLimited() {
        #expect(AdRegionLogic.region(
            storefrontCountryCode: "FR",
            deviceRegionCode: "US"
        ) == .limitedOnly)
        #expect(AdRegionLogic.region(
            storefrontCountryCode: nil,
            deviceRegionCode: "JP"
        ) == .standard)
        #expect(AdRegionLogic.region(
            storefrontCountryCode: nil,
            deviceRegionCode: nil
        ) == .limitedOnly)
    }

    @Test
    func decisionCarriesRegion() {
        let now = Self.utcDate(2024, 1, 15, 12, 0)
        let p = AdPolicy(input: input(now: now, region: .limitedOnly))
        #expect(p.canShowBanner(context: .soundsList).region == .limitedOnly)
    }

    // MARK: - AdsConfig / AdSlot

    @Test
    func adsConfig_isDisabledForThisRelease() {
        #expect(AdsConfig.isEnabled == false)
    }

    @Test
    func adSlot_rendersNothingWhileDisabled() {
        #expect(!AdSlotLayout.shouldRender(isEnabled: false, allowed: true))
        #expect(AdSlotLayout.height(isEnabled: false) == 0)
        #expect(AdSlotLayout.shouldRender(isEnabled: true, allowed: true))
        #expect(AdSlotLayout.height(isEnabled: true) == AdsConfig.bannerHeight)
    }

    // MARK: - App Group

    @Test
    func firstLaunchAndLastInterstitial_roundTrip() {
        let originalFirst = AppGroup.firstLaunchDate
        let originalLast = AppGroup.lastInterstitialShownAt
        defer {
            AppGroup.firstLaunchDate = originalFirst
            AppGroup.lastInterstitialShownAt = originalLast
        }

        let date = Self.utcDate(2024, 1, 15, 12, 0)
        AppGroup.firstLaunchDate = date
        AppGroup.lastInterstitialShownAt = date

        #expect(AppGroup.firstLaunchDate == date)
        #expect(AppGroup.lastInterstitialShownAt == date)

        AppGroup.lastInterstitialShownAt = nil
        #expect(AppGroup.lastInterstitialShownAt == nil)
    }

    // MARK: - アラーム一覧の下部バナー（2026-10-30 仕様変更）

    @Test
    func bannerAlarmList_isAllowedDuringDay() {
        let decision = policy().canShowBanner(context: .alarmList)
        #expect(decision.allowed)
        #expect(decision.reason == .eligible)
        #expect(AdContext.alarmList.slot == .bannerAlarmList)
        #expect(policy().decision(for: .bannerAlarmList).allowed)
    }

    @Test
    func bannerAlarmList_isDeniedInQuietHours() {
        let at21 = AdPolicy(input: input(now: date(2024, 1, 15, 21, 0)))
        #expect(at21.canShowBanner(context: .alarmList).reason == .quietHours)

        let at659 = AdPolicy(input: input(now: date(2024, 1, 15, 6, 59)))
        #expect(at659.canShowBanner(context: .alarmList).reason == .quietHours)
    }

    @Test
    func bannerAlarmList_isDeniedInForbiddenStates() {
        for context in [AdContext.bedside, .onboarding, .alarmRinging, .testRinging] {
            #expect(policy().canShowBanner(context: context).reason == .forbiddenContext)
        }
    }
}
