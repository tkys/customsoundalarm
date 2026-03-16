import SwiftUI

@main
struct CustomSoundAlarmApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasLaunched = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    guard !hasLaunched else { return }
                    hasLaunched = true

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
