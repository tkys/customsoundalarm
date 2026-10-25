import Foundation

/// 広告を出す場所（計測の `slot` と一致）。
enum AdSlotKind: String, Sendable, CaseIterable {
    case bannerSounds = "banner_sounds"
    case bannerImport = "banner_import"
    case interstitialImportSaved = "interstitial_import_saved"

    var isBanner: Bool {
        self == .bannerSounds || self == .bannerImport
    }

    var isInterstitial: Bool {
        self == .interstitialImportSaved
    }
}

/// 画面の種類。禁止画面もここに含める。
enum AdContext: String, Sendable, CaseIterable {
    // バナーを出してよい画面
    case soundsList
    case importScreen
    // 全画面を出してよいタイミング
    case importSaved
    // 出さない画面・状態
    case alarmList
    case bedside
    case onboarding
    case alarmRinging
    case testRinging

    var slot: AdSlotKind? {
        switch self {
        case .soundsList: .bannerSounds
        case .importScreen: .bannerImport
        case .importSaved: .interstitialImportSaved
        case .alarmList, .bedside, .onboarding, .alarmRinging, .testRinging: nil
        }
    }
}

/// 出せない理由（計測の `reason`）。
enum AdDecisionReason: String, Sendable, Equatable {
    case eligible
    case existingUser = "existing_user"
    case versionUnavailable = "version_unavailable"
    case pro
    case firstWeek = "first_week"
    case quietHours = "quiet_hours"
    case frequencyCap = "frequency_cap"
    case forbiddenContext = "forbidden_context"
    case wrongContext = "wrong_context"
}

/// 判定結果
struct AdDecision: Equatable, Sendable {
    let allowed: Bool
    let reason: AdDecisionReason
    let region: AdRegion
}

/// `AdPolicy` の入力。
struct AdPolicyInput: Equatable, Sendable {
    let now: Date
    let timeZone: TimeZone
    let firstLaunchDate: Date?
    let originalAppVersion: String?
    let introductionBuild: Int
    let isPro: Bool
    let lastInterstitialShownAt: Date?
    let region: AdRegion
}

/// 広告の表示判定（純ロジック・#111）。
///
/// 順序:
/// 1. 画面の種類（禁止画面は常に出さない）
/// 2. originalAppVersion（取得失敗・導入版より前は出さない）
/// 3. PRO
/// 4. 初回起動から7日
/// 5. 21:00〜6:59
/// 6. 全画面の週1回
struct AdPolicy {
    let input: AdPolicyInput

    init(input: AdPolicyInput) {
        self.input = input
    }

    func canShowBanner(context: AdContext) -> AdDecision {
        evaluate(context: context, expected: .banner)
    }

    func canShowInterstitial(context: AdContext) -> AdDecision {
        evaluate(context: context, expected: .interstitial)
    }

    /// slot から直接判定する（計測・枠の実装用）。
    func decision(for slot: AdSlotKind) -> AdDecision {
        switch slot {
        case .bannerSounds: canShowBanner(context: .soundsList)
        case .bannerImport: canShowBanner(context: .importScreen)
        case .interstitialImportSaved: canShowInterstitial(context: .importSaved)
        }
    }

    private enum ExpectedKind {
        case banner
        case interstitial
    }

    private func evaluate(context: AdContext, expected: ExpectedKind) -> AdDecision {
        guard let slot = context.slot else {
            return deny(.forbiddenContext)
        }
        switch expected {
        case .banner where !slot.isBanner:
            return deny(.wrongContext)
        case .interstitial where !slot.isInterstitial:
            return deny(.wrongContext)
        default:
            break
        }

        guard let originalBuild = Self.parseBuild(input.originalAppVersion) else {
            return deny(.versionUnavailable)
        }
        if originalBuild < input.introductionBuild {
            return deny(.existingUser)
        }

        if input.isPro {
            return deny(.pro)
        }

        let calendar = Self.calendar(timeZone: input.timeZone)
        guard let firstLaunch = input.firstLaunchDate else {
            return deny(.firstWeek)
        }
        if let graceEnd = calendar.date(
            byAdding: .day,
            value: AdsConfig.firstLaunchGraceDays,
            to: firstLaunch
        ), input.now < graceEnd {
            return deny(.firstWeek)
        }

        let hour = calendar.component(.hour, from: input.now)
        if hour >= AdsConfig.quietHoursStart || hour < AdsConfig.quietHoursEnd {
            return deny(.quietHours)
        }

        if slot.isInterstitial, let lastShown = input.lastInterstitialShownAt {
            if let nextAllowed = calendar.date(
                byAdding: .day,
                value: AdsConfig.interstitialMinIntervalDays,
                to: lastShown
            ), input.now < nextAllowed {
                return deny(.frequencyCap)
            }
        }

        return AdDecision(allowed: true, reason: .eligible, region: input.region)
    }

    private func deny(_ reason: AdDecisionReason) -> AdDecision {
        AdDecision(allowed: false, reason: reason, region: input.region)
    }

    private static func calendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }


    /// `originalAppVersion`（CFBundleVersion）を Int として読む。
    /// "6" のようなビルド番号のみ有効。"1.0" や空は nil（安全側で出さない）。
    static func parseBuild(_ value: String?) -> Int? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let number = Int(trimmed), number >= 0 else {
            return nil
        }
        return number
    }
}
