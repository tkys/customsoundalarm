import SwiftUI

@main
struct CustomSoundAlarmApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasRequestedAuth = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    guard !hasRequestedAuth else { return }
                    hasRequestedAuth = true
                    _ = await AlarmScheduler.shared.requestAuthorization()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        SoundStore.shared.reload()
                    }
                }
        }
    }
}
