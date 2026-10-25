import Foundation
import os

/// アプリ設定の取得（テストで差し替え可能）
protocol AppConfigFetching: Sendable {
    func fetch() async -> AppConfig?
}

/// GitHub Pages の `app-config.json` を 5 秒で取得する。
struct URLSessionAppConfigFetcher: AppConfigFetching {
    static let defaultURL = URL(string: "https://tkys.github.io/customsoundalarm/app-config.json")!

    let url: URL

    init(url: URL = Self.defaultURL) {
        self.url = url
    }

    func fetch() async -> AppConfig? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            return AppConfig(data: data)
        } catch {
            return nil
        }
    }
}

/// アップデート案内の取得・判定・表示状態（#116）。
///
/// - 起動時と前面復帰時に呼ぶ。取得は1時間に1回まで。
/// - 取得失敗・解析失敗・タイムアウト時はキャッシュで判定する。
///   キャッシュが無ければ何もしない（絶対にブロックしない）。
@Observable
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    private let logger = Logger(subsystem: "com.tkysdev.customsoundalarm", category: "UpdateGate")
    private let fetcher: AppConfigFetching
    private let now: @Sendable () -> Date

    private(set) var prompt: UpdatePrompt?

    /// 取得の最小間隔
    static let fetchInterval: TimeInterval = 60 * 60

    init(
        fetcher: AppConfigFetching = URLSessionAppConfigFetcher(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fetcher = fetcher
        self.now = now
    }

    /// 起動時・前面復帰時に呼ぶ。
    func check(isOnboardingVisible: Bool) async {
        await refreshConfigIfNeeded()

        let input = UpdateGateInput(
            currentBuild: UpdateGate.currentBuild(),
            config: cachedConfig(),
            configFetchedAt: AppGroup.cachedAppConfigFetchedAt,
            now: now(),
            dismissedRecommendedBuild: AppGroup.dismissedRecommendedBuild,
            isOnboardingVisible: isOnboardingVisible,
            isAlarmRinging: AlarmScheduler.shared.isAlarmRinging,
            isTestRinging: AlarmScheduler.shared.isTestRingActive
        )

        guard let decision = UpdateGate.decide(input) else { return }

        switch decision.kind {
        case .required:
            // 必須は常に優先する
            prompt = decision
        case .recommended:
            // 表示中の必須を上書きしない
            if prompt == nil || prompt?.kind == .recommended {
                prompt = decision
            }
        }
    }

    /// おすすめを「あとで」で閉じる。同じ latest_build では再表示しない。
    @discardableResult
    func dismissRecommended() -> UpdatePrompt? {
        guard let current = prompt, current.kind == .recommended else { return nil }
        AppGroup.dismissedRecommendedBuild = current.targetBuild
        prompt = nil
        AnalyticsService.shared.capture(.updatePromptDismissed(kind: .recommended))
        return current
    }

    /// 更新ボタン後の後処理（おすすめのみ閉じる。必須は閉じない）。
    func handleUpdateTap() {
        guard let current = prompt, current.kind == .recommended else { return }
        AppGroup.dismissedRecommendedBuild = current.targetBuild
        prompt = nil
    }

    /// テスト用に状態をリセット
    func resetPrompt() {
        prompt = nil
    }

    // MARK: - Fetch / cache

    private func refreshConfigIfNeeded() async {
        #if DEBUG
        if let override = debugConfigOverride() {
            AppGroup.cachedAppConfigData = try? JSONEncoder().encode(override)
            AppGroup.cachedAppConfigFetchedAt = now()
            AppGroup.lastUpdateCheckAt = now()
            return
        }
        #endif

        let current = now()
        if let last = AppGroup.lastUpdateCheckAt,
           current.timeIntervalSince(last) < Self.fetchInterval {
            return
        }
        AppGroup.lastUpdateCheckAt = current

        guard let fetched = await fetcher.fetch() else {
            logger.info("App config fetch failed; using cache if available")
            return
        }
        AppGroup.cachedAppConfigData = try? JSONEncoder().encode(fetched)
        AppGroup.cachedAppConfigFetchedAt = current
    }

    private func cachedConfig() -> AppConfig? {
        guard let data = AppGroup.cachedAppConfigData else { return nil }
        return AppConfig(data: data)
    }

    #if DEBUG
    /// UIテスト用: 起動引数で設定を差し込む
    private func debugConfigOverride() -> AppConfig? {
        guard let current = UpdateGate.currentBuild() else { return nil }
        if AppGroup.isUITestUpdateRequired {
            return AppConfig(minimumBuild: current + 1, latestBuild: current + 2)
        }
        if AppGroup.isUITestUpdateRecommended {
            return AppConfig(minimumBuild: 0, latestBuild: current + 1)
        }
        return nil
    }
    #endif
}
