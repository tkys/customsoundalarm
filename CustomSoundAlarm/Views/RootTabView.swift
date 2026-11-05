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
        // 文字・押せるアイコンは濃いオレンジ（#174）。タブの選択中は
        // App 側の UITabBarAppearance でブランドのオレンジに固定する。
        .tint(Color.actionText)
        // スクリーンショット撮影用の外観固定（DEBUGのみ・#173）。
        .preferredColorScheme(uiTestColorScheme)
    }

    private var uiTestColorScheme: ColorScheme? {
        #if DEBUG
        if CommandLine.arguments.contains("-uitest-force-dark") { return .dark }
        if CommandLine.arguments.contains("-uitest-force-light") { return .light }
        #endif
        return nil
    }
}
