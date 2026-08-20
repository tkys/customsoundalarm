import Foundation

/// ベッドサイドモードのセッション状態遷移（純粋関数・単体テスト対象・#71）。
///
/// 背景: `bedside_exited` は `exitMode()`（明示的終了）でしか発火せず、
/// バックグラウンド化（scenePhase != .active）では出ていなかったため、
/// 「枕元に置いて寝る」本命の使い方が測定対象外だった（実データで30%欠落）。
///
/// 本ロジックで以下を扱う:
/// - バックグラウンド化で `bedside_exited(backgrounded)` を発火
/// - 復帰時は `enterDate` を再起点（二重計上防止）
/// - `exitMode()` と `scenePhase` の両方で二重発火しない
struct BedsideSessionState: Equatable, Sendable {
    /// モード表示中か（fullScreenCover が present されているか）
    var isInMode: Bool
    /// セッションがアクティブか（フォアグラウンドで計測中か）
    var isSessionActive: Bool
    /// 現在セッションの開始時刻（バックグラウンド復帰で再起点）
    var enterDate: Date

    static func initial(now: Date) -> BedsideSessionState {
        BedsideSessionState(isInMode: false, isSessionActive: false, enterDate: now)
    }
}

/// 遷移が生じさせる計測イベント（View 側で AnalyticsEvent に変換して送信）。
enum BedsideSessionEvent: Equatable, Sendable {
    case none
    /// 入室（bedside_entered を発火する）
    case entered
    /// 退出（bedside_exited を発火する）。durationSeconds は現在セッションの滞在秒数
    case exited(durationSeconds: TimeInterval, exitMethod: BedsideExitMethod)
    /// 復帰でセッション再起点（イベントは発火しない）
    case resumed
}

/// 純粋状態遷移。各遷移は「新しい状態」と「発生するイベント」を返す。
enum BedsideSessionLogic {

    /// 入室（モード表示）。常に新規セッションを開始する。
    static func enter(now: Date) -> (state: BedsideSessionState, event: BedsideSessionEvent) {
        let state = BedsideSessionState(isInMode: true, isSessionActive: true, enterDate: now)
        return (state, .entered)
    }

    /// バックグラウンド化（scenePhase が .active 以外）。
    /// モード内かつセッションアクティブのときだけ退出イベント（backgrounded）を発火する。
    /// 連続した非アクティブ遷移や復帰後の再バックグラウンドでは二重発火しない。
    static func background(_ state: BedsideSessionState, now: Date) -> (state: BedsideSessionState, event: BedsideSessionEvent) {
        guard state.isInMode, state.isSessionActive else {
            return (state, .none)
        }
        let duration = now.timeIntervalSince(state.enterDate)
        var next = state
        next.isSessionActive = false
        return (next, .exited(durationSeconds: duration, exitMethod: .backgrounded))
    }

    /// フォアグラウンド復帰（scenePhase が .active かつモード内）。
    /// セッションが非アクティブのときだけ再起点し、`resumed`（イベントなし）を返す。
    /// 既にアクティブなら何もしない。
    static func foreground(_ state: BedsideSessionState, now: Date) -> (state: BedsideSessionState, event: BedsideSessionEvent) {
        guard state.isInMode, !state.isSessionActive else {
            return (state, .none)
        }
        var next = state
        next.isSessionActive = true
        next.enterDate = now
        return (next, .resumed)
    }

    /// 明示的終了（dismiss）。モード内なら退出イベント（exit_button / long_press）を発火する。
    /// 既にバックグラウンド化で退出済み（isSessionActive == false）の場合は、
    /// イベントを発火せず状態だけ閉じる（二重計上防止・#73 レビュー指摘）。
    static func exit(_ state: BedsideSessionState, now: Date, method: BedsideExitMethod) -> (state: BedsideSessionState, event: BedsideSessionEvent) {
        guard state.isInMode else {
            return (state, .none)
        }
        var next = state
        next.isInMode = false
        next.isSessionActive = false
        // 既に background で退出済みなら二重に発火しない
        guard state.isSessionActive else {
            return (next, .none)
        }
        let duration = now.timeIntervalSince(state.enterDate)
        return (next, .exited(durationSeconds: duration, exitMethod: method))
    }
}
