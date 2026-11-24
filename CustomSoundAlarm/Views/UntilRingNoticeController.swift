import SwiftUI
import Accessibility

/// 光っている行の2行目に、次に鳴るまでの1文を数秒だけ出す（#289）。
///
/// 行の高さを変えないよう、`metadataLine` の上に重ねてクロスフェードする。
/// 状態は「どの行に・何の文を・見えているか」だけを持つ。
@MainActor
@Observable
final class UntilRingNoticeController {
    /// 出している行。別の行に移ったら前の行は戻す。
    private(set) var alarmID: UUID?
    /// 出す1文。
    private(set) var text: String?
    /// 文が見えているか。
    private(set) var isVisible = false

    private var task: Task<Void, Never>?

    enum Timing {
        /// 出てから消え終わるまで（約3秒）
        static var visible: TimeInterval {
            AppGroup.isUITestHoldUntilRing ? 10 : 3.0
        }
        /// 消えるとき
        static let exit: TimeInterval = 0.45
        /// Reduce Motion のフェード
        static let fade: TimeInterval = 0.2
    }

    /// 指定した行に1文を出す。同じ行で続けて呼ばれたら文だけ入れ替える。
    func show(_ text: String, for alarmID: UUID) {
        task?.cancel()
        self.alarmID = alarmID
        self.text = text
        isVisible = true

        // 画面の文と同じ1文を読み上げる（行の accessibilityLabel は変えない）
        AccessibilityNotification.Announcement(text).post()
        scheduleHide()
    }

    private func scheduleHide() {
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(
                for: .seconds(Timing.visible - Timing.exit)
            )
            guard !Task.isCancelled else { return }
            self?.isVisible = false
            try? await Task.sleep(for: .seconds(Timing.exit))
            guard !Task.isCancelled else { return }
            self?.alarmID = nil
            self?.text = nil
        }
    }
}
