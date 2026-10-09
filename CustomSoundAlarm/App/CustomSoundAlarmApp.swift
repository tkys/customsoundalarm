import SwiftUI

@main
struct CustomSoundAlarmApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasLaunched = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    guard !hasLaunched else { return }
                    hasLaunched = true

#if DEBUG
                    // UIテスト用: fresh onboarding で起動されたら永続化をクリアして空状態にする
                    if AppGroup.isUITestFreshOnboarding {
                        AppGroup.hasCompletedOnboarding = false
                        AlarmStore.shared.resetForUITest()
                        SoundStore.shared.resetForUITest()
                    }
                    // UIテスト用: アラーム一覧を時刻順で検証するためのシード
                    if AppGroup.isUITestSeedAlarms {
                        AppGroup.hasCompletedOnboarding = true
                        AlarmStore.shared.resetForUITest()
                        let seeds: [(Int, Int)] = [(23, 44), (6, 24), (18, 0)]
                        for (h, m) in seeds {
                            let alarm = AlarmEntry(hour: h, minute: m)
                            AlarmStore.shared.add(alarm)
                        }
                    }
#endif

                    // PostHog 計測の初期化（Info.plist にキーが無い場合は安全に無効化）
                    AnalyticsService.shared.configure()
                    setUserProperties()

                    // #98: オンボの要否は Entitlements のネットワーク待ちより前に
                    // 同期的に決める（ContentView も即座に同じ入力で判定する。await の後で
                    // App が評価するとレースし、ユーザーがオンボ完了後に二重で
                    // reconcile/sync/startObserving が走る恐れがある — レビュー指摘2）
#if DEBUG
                    let effectiveHasCompletedForLaunch: Bool
                    if AppGroup.isUITestFreshOnboarding {
                        effectiveHasCompletedForLaunch = false
                    } else {
                        effectiveHasCompletedForLaunch = AppGroup.hasCompletedOnboarding
                    }
#else
                    let effectiveHasCompletedForLaunch = AppGroup.hasCompletedOnboarding
#endif
                    let showsOnboardingAtLaunch = OnboardingLogic.shouldShow(
                        hasCompleted: effectiveHasCompletedForLaunch,
                        alarmCount: AlarmStore.shared.alarms.count,
                        importedSoundCount: SoundStore.shared.sounds.filter { !$0.isPreset }.count
                    )
                    if OnboardingLogic.shouldMarkCompleted(
                        hasCompleted: AppGroup.hasCompletedOnboarding,
                        shouldShowOnboarding: showsOnboardingAtLaunch
                    ) {
                        // 既存ユーザー（アップデートで来た人）は初回起動時に完了扱いにして以後出さない
                        AppGroup.hasCompletedOnboarding = true
                    }

                    // 課金権利の監視開始（Transaction.updates）と最新化
                    // StoreKit の作法: 起動のできるだけ早い段階で監視を開始し、
                    // アプリ外で完了したトランザクション（Ask to Buy 等）を受け取る
                    Entitlements.shared.startObservingUpdates()
                    await Entitlements.shared.refresh()

                    // #98 Phase 1: オンボを出す人は許可要求を場面3へ移す（価値を見せてから聞く）
                    if OnboardingLogic.shouldRequestAuthorizationAtLaunch(shouldShowOnboarding: showsOnboardingAtLaunch) {
                        let authorized = await AlarmScheduler.shared.requestAuthorization()
                        if authorized {
                            // 起動時: AlarmKit と AlarmStore の整合性チェック
                            // （キル中に発火した一回限りアラームを自動 OFF）
                            AlarmScheduler.shared.reconcileOnLaunch()
                            // AlarmKit に現在の設定を反映
                            AlarmScheduler.shared.syncAlarms(AlarmStore.shared.alarms)
                            // 一回限りアラーム発火後の自動 OFF を監視
                            AlarmScheduler.shared.startObservingAlarmStates()
                        }
                    }
                    // オンボを出す人は場面3で「続ける」を押した時点で
                    // requestAuthorization → reconcileOnLaunch / syncAlarms / startObservingAlarmStates
                    // を同じ順に実行する（OnboardingView 側）
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        // Share Extension 等の外部変更を反映
                        SoundStore.shared.reload()
                        // データが変わった場合のみ AlarmKit と再同期
                        let changed = AlarmStore.shared.reload()
                        if changed {
                            AlarmScheduler.shared.syncAlarms(AlarmStore.shared.alarms)
                        }
                    }
                }
        }
    }
}

// MARK: - User Properties

@MainActor
private func setUserProperties() {
    // 初回インストールバージョンを記録（一度だけ）
    if AppGroup.firstInstallVersion == nil {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        AppGroup.firstInstallVersion = version
    }

    AnalyticsService.shared.setUserProperties(userPropertiesPayload())

    // 既存のカスタム音源で秒数が未記録のものがある場合のみ、一度だけ遅延バックフィルして再送する。
    // 起動直後のクリティカルパスを重くしないため 1 秒遅延させ、計測済み音源は対象外なので
    // 起動のたびに全ファイルを読むことはない（#68・追加時記録との併用）。
    if SoundStore.shared.hasMissingDurations() {
        Task {
            try? await Task.sleep(for: .seconds(1))
            if SoundStore.shared.backfillMissingDurations() {
                AnalyticsService.shared.setUserProperties(userPropertiesPayload())
            }
        }
    }
}

/// ユーザープロパティのペイロードを組み立てる。
/// サウンドの長さ・件数の分布は区分（バケット）で送る（生の秒数は不要・#68）。
@MainActor
private func userPropertiesPayload() -> [String: Any] {
    let customSounds = SoundStore.shared.sounds.filter { !$0.isPreset }
    let durations = customSounds.compactMap(\.durationSeconds)
    let totalSeconds = durations.reduce(0, +)
    let maxSeconds = durations.max()

    let customSoundCount = customSounds.count
    let alarmCount = AlarmStore.shared.alarms.count
    let firstVersion = AppGroup.firstInstallVersion ?? "unknown"

    return [
        "custom_sound_count": customSoundCount,
        "alarm_count": alarmCount,
        "first_install_version": firstVersion,
        "sound_total_seconds_bucket": AnalyticsBuckets.secondsBucket(seconds: totalSeconds),
        "sound_max_seconds_bucket": maxSeconds.map { AnalyticsBuckets.secondsBucket(seconds: $0) }
            ?? AnalyticsBuckets.secondsBucket(seconds: 0)
    ]
}
