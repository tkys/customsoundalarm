import SwiftUI
import Accessibility

/// 一覧の上に数秒だけ出す、次に鳴るまでの1文（#289）。
///
/// 行を光らせる流れ（#282）に合わせて、スクロールが止まって光るときに
/// フェードインし、約3秒でフェードアウトする。出入りは加速・減速の曲線。
/// Reduce Motion では移動を付けず、フェードだけで出す。
@MainActor
@Observable
final class UntilRingNoticeController {
    /// 出す1文。空になったら一覧から消す。
    private(set) var text: String?
    /// 一覧の上に場所を空けているか（高さ）。
    private(set) var isPlaced = false
    /// 文が見えているか（不透明度）。
    private(set) var isVisible = false

    private var task: Task<Void, Never>?

    enum Timing {
        /// 出てから消え終わるまで（約3秒）
        static let visible: TimeInterval = 3.0
        /// 出るとき
        static let enter: TimeInterval = 0.35
        /// 消えるとき
        static let exit: TimeInterval = 0.45
        /// Reduce Motion のフェード
        static let fade: TimeInterval = 0.2
    }

    /// シートが閉じる前に場所だけ空けておく（#282 のスクロール位置に合わせるため）。
    /// 文はまだ見せない。
    func prepare(_ text: String) {
        task?.cancel()
        task = nil
        self.text = text
        isVisible = false
        isPlaced = true
    }

    /// 場所を空けた文を出す。スクロールが止まって光るときに呼ぶ。
    func reveal() {
        guard let text else { return }
        task?.cancel()
        isVisible = true
        // 画面の文と同じ1文を読み上げる
        AccessibilityNotification.Announcement(text).post()
        scheduleHide()
    }

    /// 場所を空けて、すぐ出す（一覧でオンにしたとき・空の一覧からの作成）。
    func show(_ text: String) {
        // 続けて操作したときは、消して出し直さず文だけ入れ替える
        if isVisible {
            task?.cancel()
            self.text = text
            isPlaced = true
            AccessibilityNotification.Announcement(text).post()
            scheduleHide()
            return
        }

        prepare(text)
        // 場所が決まってから出す（高さ0のままフェードインしない）
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            self?.reveal()
        }
    }

    private func scheduleHide() {
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(
                for: .seconds(Timing.visible - Timing.exit)
            )
            guard !Task.isCancelled else { return }
            self?.isVisible = false
            self?.isPlaced = false
            try? await Task.sleep(for: .seconds(Timing.exit))
            guard !Task.isCancelled else { return }
            self?.text = nil
        }
    }
}

/// 一覧の上に置く、余計な装飾のない1文（#289）。
struct UntilRingNoticeView: View {
    let text: String
    let isPlaced: Bool
    let isVisible: Bool
    let reduceMotion: Bool

    @State private var naturalHeight: CGFloat = 0

    var body: some View {
        content
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { naturalHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, height in
                            naturalHeight = height
                        }
                }
            }
            .frame(
                height: isPlaced ? naturalHeight : 0,
                alignment: .top
            )
            .clipped()
            .opacity(isVisible ? 1 : 0)
            .animation(placementAnimation, value: isPlaced)
            .animation(visibilityAnimation, value: isVisible)
            .animation(fadeAnimation, value: naturalHeight)
            .accessibilityHidden(!isVisible)
            .allowsHitTesting(false)
    }

    private var content: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .accessibilityIdentifier("alarmList.untilRing")
    }

    private var placementAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: UntilRingNoticeController.Timing.fade)
            : .timingCurve(
                0.05, 0.7, 0.1, 1,
                duration: UntilRingNoticeController.Timing.enter
            )
    }

    private var visibilityAnimation: Animation {
        if reduceMotion {
            return .easeInOut(duration: UntilRingNoticeController.Timing.fade)
        }
        return isVisible
            ? .timingCurve(
                0.05, 0.7, 0.1, 1,
                duration: UntilRingNoticeController.Timing.enter
            )
            : .timingCurve(
                0.4, 0, 0.2, 1,
                duration: UntilRingNoticeController.Timing.exit
            )
    }

    private var fadeAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: UntilRingNoticeController.Timing.fade)
            : .timingCurve(
                0.05, 0.7, 0.1, 1,
                duration: UntilRingNoticeController.Timing.enter
            )
    }
}
