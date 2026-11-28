import Foundation
import os

/// プレイリストの解放シートの表示と計測（#216 / #280）。
@Observable
@MainActor
final class PlaylistUnlockCoordinator {
    static let shared = PlaylistUnlockCoordinator()

    private let logger = Logger(subsystem: "com.tkysdev.customsoundalarm", category: "PlaylistUnlock")

    /// シートを表示中か。
    var isPresented = false
    /// 「作る」で作ったプレイリスト。詳細を開くために一度だけ取り出す。
    private(set) var createdPlaylistID: UUID?
    /// この表示のきっかけ。行動の計測に付ける（#280）。
    private var trigger: PlaylistUnlockTrigger = .secondImport
    /// この表示で create / later のどちらかを送ったか。
    private var didRecordAction = false

    private init() {}

    /// 条件を満たすときだけシートを表示する。表示したら二度と出さない。
    @discardableResult
    func presentIfNeeded(
        isRinging: Bool,
        isNightMode: Bool,
        hasAnotherSheet: Bool = false
    ) -> Bool {
        guard !isPresented, !AppGroup.playlistUnlockShown else { return false }
        #if DEBUG
        // UIテストでは、解放の確認をするテストだけ有効にする（#216 / #280）
        guard !AppGroup.isUITestRun || AppGroup.isUITestPlaylistUnlock else { return false }
        #endif

        let hasFiredAlarm = FirstAlarmFollowupLogic.hasFiredAlarm(
            historyLines: AlarmLocalHistoryStore.recentLines(
                limit: AlarmLocalHistoryStore.maxLines
            )
        )
        let trigger = PlaylistUnlockLogic.trigger(
            hasPending: SoundStore.shared.hasPendingPlaylistUnlock,
            hasFiredAlarm: hasFiredAlarm,
            customSoundCount: SoundStore.shared.customSoundCount,
            playlistCount: PlaylistStore.shared.playlists.count,
            hasShown: AppGroup.playlistUnlockShown
        )
        guard let trigger,
              PlaylistUnlockLogic.canPresent(
                  trigger: trigger,
                  isRinging: isRinging,
                  isNightMode: isNightMode,
                  hasAnotherSheet: hasAnotherSheet
              ) else { return false }

        AppGroup.playlistUnlockShown = true
        SoundStore.shared.clearPendingPlaylistUnlock()
        didRecordAction = false
        createdPlaylistID = nil
        self.trigger = trigger
        AnalyticsService.shared.capture(.featureUnlockShown(
            feature: .playlist,
            trigger: trigger,
            firedBefore: hasFiredAlarm
        ))
        isPresented = true
        logger.info("Playlist unlock presented (trigger: \(trigger.rawValue, privacy: .public))")
        return true
    }

    #if DEBUG
    /// スクリーンショット用に、条件を飛ばしてシートを出す（#216）。
    func presentForUITest() {
        AppGroup.playlistUnlockShown = true
        SoundStore.shared.clearPendingPlaylistUnlock()
        didRecordAction = false
        createdPlaylistID = nil
        trigger = .existingUser
        isPresented = true
    }
    #endif

    /// 「この2つでプレイリストを作る」。
    func create() {
        didRecordAction = true
        AnalyticsService.shared.capture(.featureUnlockAction(
            feature: .playlist,
            action: .create,
            trigger: trigger
        ))
        createdPlaylistID = PlaylistSuggestionService.create(source: .unlock)?.id
        isPresented = false
    }

    /// 「あとで」。
    func later() {
        didRecordAction = true
        AnalyticsService.shared.capture(.featureUnlockAction(
            feature: .playlist,
            action: .later,
            trigger: trigger
        ))
        isPresented = false
    }

    /// スワイプや外のタップで閉じたとき。ボタンで送っていれば二重に送らない。
    func handleDismiss() {
        if !didRecordAction {
            AnalyticsService.shared.capture(.featureUnlockAction(
                feature: .playlist,
                action: .later,
                trigger: trigger
            ))
        }
        didRecordAction = false
    }

    /// 作成したプレイリストの ID を一度だけ返す。
    func takeCreatedPlaylistID() -> UUID? {
        defer { createdPlaylistID = nil }
        return createdPlaylistID
    }
}

/// ナイトモード（ベッドサイド）表示中か（#216）。
@Observable
@MainActor
final class BedsideModeTracker {
    static let shared = BedsideModeTracker()
    var isActive = false
    private init() {}
}
