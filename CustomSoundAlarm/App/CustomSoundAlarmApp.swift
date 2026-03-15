import SwiftUI

@main
struct CustomSoundAlarmApp: App {
    @State private var hasRequestedAuth = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    guard !hasRequestedAuth else { return }
                    hasRequestedAuth = true
                    _ = await AlarmScheduler.shared.requestAuthorization()
                }
        }
    }
}
