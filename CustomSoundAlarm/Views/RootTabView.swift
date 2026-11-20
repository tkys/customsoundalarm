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
    @State private var unlock = PlaylistUnlockCoordinator.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// 解放シートの表示（coordinator の変更をローカル状態に写す・#216）
    @State private var showingUnlock = false
    /// 解放から作ったプレイリストの詳細（#216）
    @State private var unlockPlaylist: Playlist?
    @State private var shareLanding = ShareImportLanding.shared
    /// スクリーンショット用（DEBUGのみ・#239）
    @State private var showingShareReceipt = false
    /// コントロールセンターから開く要求（#272）
    @State private var controlOpenKind: ControlOpenKind?

    var body: some View {
        TabView(selection: $selection) {
            ContentView(controlOpenKind: $controlOpenKind)
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
        .task {
            #if DEBUG
            if AppGroup.isUITestControlList {
                handleControlOpen(.list)
            } else if AppGroup.isUITestControlAdd {
                handleControlOpen(.add)
            }
            if AppGroup.isUITestShowShareReceipt {
                showingShareReceipt = true
            }
            if AppGroup.isUITestShowPlaylistUnlock {
                try? await Task.sleep(for: .milliseconds(500))
                unlock.presentForUITest()
            }
            #endif
        }
        .onChange(of: unlock.isPresented) { _, isPresented in
            showingUnlock = isPresented
        }
        .onChange(of: shareLanding.librarySoundFileName) { _, fileName in
            if fileName != nil { selection = .library }
        }
        .onChange(of: shareLanding.addAlarmSound) { _, sound in
            if sound != nil { selection = .alarms }
        }
        .onOpenURL { url in
            if let kind = ControlOpenLogic.kind(from: url) {
                handleControlOpen(kind)
            }
        }
        .sheet(isPresented: $showingUnlock, onDismiss: {
            if unlock.isPresented {
                unlock.isPresented = false
            }
            unlock.handleDismiss()
            if let id = unlock.takeCreatedPlaylistID(),
               let playlist = PlaylistStore.shared.playlist(id: id) {
                unlockPlaylist = playlist
            }
        }) {
            PlaylistUnlockSheet(
                onCreate: { unlock.create() },
                onLater: { unlock.later() }
            )
            .presentationDetents(
                dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium]
            )
        }
        .sheet(item: $unlockPlaylist) { playlist in
            NavigationStack {
                PlaylistEditorView(playlist: playlist, onSave: { _ in })
            }
        }
        #if DEBUG
        .fullScreenCover(isPresented: $showingShareReceipt) {
            ShareReceiptPreviewView()
        }
        #endif
    }

    /// コントロールから起動したときの入口（#272）。
    /// 一覧はアラームタブ、追加は ContentView が追加画面を出す。
    private func handleControlOpen(_ kind: ControlOpenKind) {
        selection = .alarms
        AnalyticsService.shared.capture(.controlOpened(kind: kind))
        controlOpenKind = kind
    }

    private var uiTestColorScheme: ColorScheme? {
        #if DEBUG
        if CommandLine.arguments.contains("-uitest-force-dark") { return .dark }
        if CommandLine.arguments.contains("-uitest-force-light") { return .light }
        #endif
        return nil
    }
}
