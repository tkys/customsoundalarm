import Testing
import Foundation
@testable import CustomSoundAlarm

/// `BedsideSessionLogic` の状態遷移を検証する（#71）。
/// 入室→バックグラウンド→復帰→退出 の一連の流れで二重計上・二重発火しないことを担保する。
struct BedsideSessionLogicTests {

    private var t0: Date { Date(timeIntervalSince1970: 1_000) }
    private var t1: Date { t0.addingTimeInterval(30) }   // 30秒後
    private var t2: Date { t1.addingTimeInterval(120) }  // さらに2分後
    private var t3: Date { t2.addingTimeInterval(300) }  // さらに5分後

    // MARK: - enter

    @Test
    func enter_startsActiveSessionAndEmitsEntered() {
        let result = BedsideSessionLogic.enter(now: t0)

        #expect(result.state.isInMode == true)
        #expect(result.state.isSessionActive == true)
        #expect(result.state.enterDate == t0)
        #expect(result.event == .entered)
    }

    // MARK: - background（バックグラウンド化）

    @Test
    func background_whileActive_emitsBackgroundedExit() {
        let entered = BedsideSessionLogic.enter(now: t0).state

        let result = BedsideSessionLogic.background(entered, now: t1)

        #expect(result.state.isInMode == true)
        #expect(result.state.isSessionActive == false)
        // 滞在時間は現在セッション（t0→t1）の30秒
        #expect(result.event == .exited(durationSeconds: 30, exitMethod: .backgrounded))
    }

    @Test
    func background_twice_doesNotDoubleFire() {
        let entered = BedsideSessionLogic.enter(now: t0).state
        let backgrounded = BedsideSessionLogic.background(entered, now: t1)

        // 連続する非アクティブ遷移（.inactive → .background）でも1回しか発火しない
        let second = BedsideSessionLogic.background(backgrounded.state, now: t2)

        #expect(second.event == .none)
        #expect(second.state.isSessionActive == false)
    }

    @Test
    func background_whenNotInMode_doesNothing() {
        let initial = BedsideSessionState.initial(now: t0)

        let result = BedsideSessionLogic.background(initial, now: t1)

        #expect(result.event == .none)
        #expect(result.state == initial)
    }

    @Test
    func background_whenAlreadyInactive_doesNothing() {
        let entered = BedsideSessionLogic.enter(now: t0).state
        let backgrounded = BedsideSessionLogic.background(entered, now: t1).state

        let again = BedsideSessionLogic.background(backgrounded, now: t2)

        #expect(again.event == .none)
    }

    // MARK: - foreground（復帰）

    @Test
    func foreground_afterBackground_resumesSessionWithoutEvent() {
        let entered = BedsideSessionLogic.enter(now: t0).state
        let backgrounded = BedsideSessionLogic.background(entered, now: t1).state

        let result = BedsideSessionLogic.foreground(backgrounded, now: t2)

        // イベントは発火しない（enterDate の再起点のみ）
        #expect(result.event == .resumed)
        #expect(result.state.isSessionActive == true)
        #expect(result.state.isInMode == true)
        // 再起点された（復帰時刻 t2 が新たな開始）
        #expect(result.state.enterDate == t2)
    }

    @Test
    func foreground_whenAlreadyActive_doesNothing() {
        let entered = BedsideSessionLogic.enter(now: t0).state

        let result = BedsideSessionLogic.foreground(entered, now: t1)

        #expect(result.event == .none)
        #expect(result.state.enterDate == t0)
    }

    @Test
    func foreground_whenNotInMode_doesNothing() {
        let initial = BedsideSessionState.initial(now: t0)

        let result = BedsideSessionLogic.foreground(initial, now: t1)

        #expect(result.event == .none)
        #expect(result.state == initial)
    }

    // MARK: - exit（明示的終了）

    @Test
    func exit_afterFullCycle_noDoubleCount() {
        // 入室 → バックグラウンド → 復帰（再起点）→ 明示終了
        let entered = BedsideSessionLogic.enter(now: t0).state
        let backgrounded = BedsideSessionLogic.background(entered, now: t1).state
        let resumed = BedsideSessionLogic.foreground(backgrounded, now: t2).state

        let result = BedsideSessionLogic.exit(resumed, now: t3, method: .exitButton)

        // 滞在時間は復帰後（t2→t3）の300秒。バックグラウンド中（t1→t2）の120秒は二重計上されない
        #expect(result.event == .exited(durationSeconds: 300, exitMethod: .exitButton))
        #expect(result.state.isInMode == false)
        #expect(result.state.isSessionActive == false)
    }

    @Test
    func exit_afterEnter_emitsExitedWithMethod() {
        let entered = BedsideSessionLogic.enter(now: t0).state

        let result = BedsideSessionLogic.exit(entered, now: t1, method: .longPress)

        #expect(result.event == .exited(durationSeconds: 30, exitMethod: .longPress))
        #expect(result.state.isInMode == false)
    }

    @Test
    func exit_whenNotInMode_doesNothing() {
        let initial = BedsideSessionState.initial(now: t0)

        let result = BedsideSessionLogic.exit(initial, now: t1, method: .exitButton)

        #expect(result.event == .none)
    }

    @Test
    func exit_afterBackgrounded_doesNotDoubleFire() {
        // バックグラウンドで退出済み（exited(backgrounded) 発火済み）のため、
        // 復帰せず明示終了しても退出イベントは発火せず、状態だけ閉じる（二重計上防止・#73）
        let entered = BedsideSessionLogic.enter(now: t0).state
        let backgrounded = BedsideSessionLogic.background(entered, now: t1).state

        let result = BedsideSessionLogic.exit(backgrounded, now: t2, method: .exitButton)

        #expect(result.event == .none)
        #expect(result.state.isInMode == false)
        #expect(result.state.isSessionActive == false)
    }

    // MARK: - BedsideExitMethod.backgrounded

    @Test
    func backgroundedRawValueIsStable() {
        #expect(BedsideExitMethod.backgrounded.rawValue == "backgrounded")
    }
}
