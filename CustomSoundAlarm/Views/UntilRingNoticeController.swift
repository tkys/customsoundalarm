import SwiftUI
import Accessibility

/// 一覧の下に数秒だけ浮かせる、次に鳴るまでの1文（#289）。
///
/// 一覧の配置は動かさず、休む（skip）のトーストと同じ位置・同じ見た目で出す。
/// 行を光らせる流れ（#282）に合わせて、スクロールが止まって光るときに
/// フェードインし、約3秒でフェードアウトする。
@MainActor
@Observable
final class UntilRingNoticeController {
    /// 出す1文。空になったら画面から消す。
    private(set) var text: String?
    /// 文が見えているか。
    private(set) var isVisible = false

    private var task: Task<Void, Never>?

    enum Timing {
        /// 出てから消え終わるまで（約3秒）
        static let visible: TimeInterval = 3.0
        /// 消えるとき
        static let exit: TimeInterval = 0.45
        /// Reduce Motion のフェード
        static let fade: TimeInterval = 0.2
    }

    /// 場所を空けずに、その場で出す（一覧でオンにしたとき・空の一覧からの作成）。
    func show(_ text: String) {
        // 続けて操作したときは、消して出し直さず文だけ入れ替える
        if isVisible {
            task?.cancel()
            self.text = text
            AccessibilityNotification.Announcement(text).post()
            scheduleHide()
            return
        }

        self.text = text
        // 挿入のトランジションを効かせるため、1フレーム置いてから出す
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            self?.reveal()
        }
    }

    /// スクロールが止まって光るときに、準備した1文を出す。
    func reveal() {
        guard let text else { return }
        task?.cancel()
        isVisible = true
        // 画面の文と同じ1文を読み上げる
        AccessibilityNotification.Announcement(text).post()
        scheduleHide()
    }

    /// 休むのトーストなど、別の一言に譲るときにすぐ消す。
    func dismiss() {
        task?.cancel()
        task = nil
        isVisible = false
        text = nil
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
            self?.text = nil
        }
    }
}
