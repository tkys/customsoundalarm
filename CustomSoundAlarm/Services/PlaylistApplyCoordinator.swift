import Foundation
import os

/// プレイリストを作ったあとの「使うアラームを選ぶ」の受け口（#324）。
/// 解放カードとライブラリの提案、どちらから作っても同じシートを出す。
@Observable
@MainActor
final class PlaylistApplyCoordinator {
    struct Request: Identifiable, Equatable {
        let id = UUID()
        let playlistID: UUID
        let source: PlaylistApplySource
    }

    static let shared = PlaylistApplyCoordinator()

    private let logger = Logger(subsystem: "com.tkysdev.customsoundalarm", category: "PlaylistApply")

    /// 表示するシート。nil なら閉じている。
    var request: Request?
    /// アラームが0本のときに、追加画面へ渡すプレイリスト（#324）。
    var pendingAddAlarmPlaylistID: UUID?

    private init() {}

    /// プレイリストを作った直後に呼ぶ。アラームが0本ならシートを出さず、追加画面へ渡す。
    func offer(playlist: Playlist, source: PlaylistApplySource) {
        let alarmCount = AlarmStore.shared.alarms.count
        AnalyticsService.shared.capture(.playlistApplyShown(
            source: source,
            alarmCountBucket: PlaylistApplyAlarmCountBucket(count: alarmCount)
        ))

        if PlaylistApplyLogic.shouldOpenAddAlarm(alarmCount: alarmCount) {
            pendingAddAlarmPlaylistID = playlist.id
            logger.info("Playlist apply opens add alarm (source: \(source.rawValue, privacy: .public))")
            return
        }
        request = Request(playlistID: playlist.id, source: source)
    }

    /// シートを閉じたとき。行動と選んだ本数を1回だけ送る。
    func finish(_ action: PlaylistApplyAction, selectedCount: Int) {
        AnalyticsService.shared.capture(.playlistApplyAction(
            action: action,
            selectedCount: selectedCount
        ))
        request = nil
    }

    /// 追加画面へ渡すプレイリストを一度だけ取り出す。
    func takePendingAddAlarmPlaylistID() -> UUID? {
        defer { pendingAddAlarmPlaylistID = nil }
        return pendingAddAlarmPlaylistID
    }
}
