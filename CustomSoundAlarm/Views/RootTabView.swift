import SwiftUI

/// ルートのタブ（#160 PR-2）。アラームとライブラリ。
enum RootTab: Hashable {
    case alarms
    case library
}

struct RootTabView: View {
    @State private var selection: RootTab = {
        #if DEBUG
        if AppGroup.isUITestOpenLibrary { return .library }
        #endif
        return .alarms
    }()

    var body: some View {
        TabView(selection: $selection) {
            ContentView()
                .tabItem {
                    Label(String(localized: "alarm_title"), systemImage: "alarm.fill")
                }
                .tag(RootTab.alarms)

            LibraryView()
                .tabItem {
                    Label(String(localized: "library_title"), systemImage: "music.note.list")
                }
                .tag(RootTab.library)
        }
    }
}
