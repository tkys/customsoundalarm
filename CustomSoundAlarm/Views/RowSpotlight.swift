import SwiftUI
import UIKit

/// 行を一度だけ静かに光らせる共通部品（#282）。
///
/// アラームの新規作成・時刻の編集・共有後の着地（#246）・連続作成（#198）で使う。
/// 時間とカーブはここにまとめ、行には光らせる部品を付けるだけで使える。
enum RowSpotlightTiming {
    // MARK: 光り方（オーナー決定・2）

    /// 立ち上がり
    static let rise: TimeInterval = 0.35
    /// 光ったまま保つ
    static let hold: TimeInterval = 0.4
    /// 消え方
    static let fade: TimeInterval = 1.6

    /// 行の背景に重ねるアクセントの濃さ
    static let accentOpacity: Double = 0.11

    /// 行が入り終わってから点け始めるまでの間
    static let glowDelayAfterReveal: TimeInterval = 0.08

    static let riseAnimation: Animation = .timingCurve(0.05, 0.7, 0.1, 1, duration: rise)
    static let fadeAnimation: Animation = .timingCurve(0.4, 0, 0.2, 1, duration: fade)

    // MARK: スクロール（オーナー決定・D）

    /// 距離に関係なく足す基本の時間
    static let scrollBase: TimeInterval = 0.45
    /// 距離1ptあたりに足す時間の分母
    static let scrollDistanceFactor: CGFloat = 1400
    static let scrollMinimum: TimeInterval = 0.5
    static let scrollMaximum: TimeInterval = 1.0

    /// 共有後の着地（#246）で使うスクロール位置（アラームの追加は最小移動・#282）
    static let scrollAnchor = UnitPoint(x: 0.5, y: 0.45)
    /// 行を画面内に残すときの上下の余白（#282）
    static let minimumVisibleInset: CGFloat = 24

    /// 距離からスクロール時間を求める（0.5〜1.0秒）。
    static func scrollDuration(for distance: CGFloat) -> TimeInterval {
        let extra = TimeInterval(max(0, distance) / scrollDistanceFactor)
        return min(scrollMaximum, max(scrollMinimum, scrollBase + extra))
    }

    /// 動き出しはゆっくり、止まり際は長く減速するカーブ。
    static func scrollAnimation(duration: TimeInterval) -> Animation {
        .timingCurve(0.33, 0, 0.15, 1, duration: duration)
    }

    // MARK: 行の入り方

    static let revealHeight: TimeInterval = 0.35
    static let revealOpacity: TimeInterval = 0.3
    static let revealHeightAnimation: Animation =
        .timingCurve(0.05, 0.7, 0.1, 1, duration: revealHeight)
    static let revealOpacityAnimation: Animation = .easeOut(duration: revealOpacity)
}

/// 行が一覧の見えている範囲に対してどこにあるか（#282）。
enum RowSpotlightPosition: Equatable, Sendable {
    case fullyVisible
    case above
    case below
    /// まだ一覧に配置されていない（遠くて行が作られていない）
    case notMeasured
}

/// スクロールするかどうかの判定（純ロジック・#282）。
enum RowSpotlightLogic {
    /// 行の矩形と一覧の見えている矩形（どちらも画面座標）から位置を返す。
    static func position(rowFrame: CGRect?, viewport: CGRect) -> RowSpotlightPosition {
        guard let rowFrame, !rowFrame.isEmpty else { return .notMeasured }
        if rowFrame.minY < viewport.minY { return .above }
        if rowFrame.maxY > viewport.maxY { return .below }
        return .fullyVisible
    }

    /// 行が全部見えていなければスクロールする。見えているなら動かさない。
    static func shouldScroll(rowFrame: CGRect?, viewport: CGRect) -> Bool {
        position(rowFrame: rowFrame, viewport: viewport) != .fullyVisible
    }

    /// 行を 45% の位置へ送るために動かす距離（pt）。
    static func scrollDistance(rowFrame: CGRect?, viewport: CGRect) -> CGFloat {
        guard let rowFrame else { return 0 }
        let targetY = viewport.minY + viewport.height * 0.45
        return abs(rowFrame.minY - targetY)
    }
}

/// 光らせる場面かどうか（#282）。新規作成と、時刻を変えた編集だけ。
enum AlarmSpotlightLogic {
    static func shouldSpotlight(
        isNew: Bool,
        oldHour: Int?,
        oldMinute: Int?,
        newHour: Int,
        newMinute: Int
    ) -> Bool {
        if isNew { return true }
        guard let oldHour, let oldMinute else { return true }
        return oldHour != newHour || oldMinute != newMinute
    }
}

/// 1行分の光り方を進める（#282）。行ごとに1つ持つ。
@MainActor
@Observable
final class RowSpotlightController {
    /// 消え終わるまで true。行の背景を出しておくために使う。
    private(set) var isActive = false
    /// 色を重ねているか。`withAnimation` で立ち上げ・フェードする。
    private(set) var isLit = false

    private var task: Task<Void, Never>?

    /// 1回だけ光らせる。
    /// - Parameter startDelay: 行が入り終わるまでの待ち時間。
    func play(startDelay: TimeInterval = 0) {
        task?.cancel()
        isActive = true
        isLit = false
        task = Task { @MainActor [weak self] in
            if startDelay > 0 {
                try? await Task.sleep(for: .seconds(startDelay))
                guard !Task.isCancelled else { return }
            }
            withAnimation(RowSpotlightTiming.riseAnimation) {
                self?.isLit = true
            }
            try? await Task.sleep(
                for: .seconds(RowSpotlightTiming.rise + RowSpotlightTiming.hold)
            )
            guard !Task.isCancelled else { return }
            withAnimation(RowSpotlightTiming.fadeAnimation) {
                self?.isLit = false
            }
            try? await Task.sleep(for: .seconds(RowSpotlightTiming.fade))
            guard !Task.isCancelled else { return }
            self?.isActive = false
        }
    }

    /// 途中で止める。
    func stop() {
        task?.cancel()
        task = nil
        isLit = false
        isActive = false
    }
}

/// 行ごとの `RowSpotlightController` を保つ（#282 / #198 のまとめて点灯用）。
@MainActor
@Observable
final class RowSpotlightStore {
    private var controllers: [UUID: RowSpotlightController] = [:]

    func controller(for id: UUID) -> RowSpotlightController {
        if let existing = controllers[id] { return existing }
        let controller = RowSpotlightController()
        controllers[id] = controller
        return controller
    }

    /// 1本、または同時に複数（#198）を光らせる。
    func play(_ ids: [UUID], startDelay: TimeInterval = 0) {
        for id in ids {
            controller(for: id).play(startDelay: startDelay)
        }
    }
}

/// 行の矩形を覚えておく（#282）。読み書きはスクロール判定のときだけなので、
/// スクロール中に一覧全体を再描画させないよう Observable にはしない。
@MainActor
final class RowFrameStore<Key: Hashable> {
    private var frames: [Key: CGRect] = [:]

    func update(_ key: Key, frame: CGRect) {
        frames[key] = frame
    }

    func frame(for key: Key) -> CGRect? {
        frames[key]
    }
}

/// 光らせる色（#282）。行の背景に重ねる。
enum RowSpotlightStyle {
    static let accent = Color.actionFillEnd.opacity(RowSpotlightTiming.accentOpacity)
}

/// 行の上にアクセント色を重ねる（#282）。
struct RowSpotlightModifier: ViewModifier {
    let controller: RowSpotlightController
    var cornerRadius: CGFloat?

    func body(content: Content) -> some View {
        content.overlay {
            Group {
                if let cornerRadius {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(RowSpotlightStyle.accent)
                } else {
                    Rectangle().fill(RowSpotlightStyle.accent)
                }
            }
            .opacity(controller.isLit ? 1 : 0)
            .allowsHitTesting(false)
        }
    }
}

/// スクロールが止まってから、高さ0から行を開く（#282）。
///
/// 閉じている間も中身は自然な高さで組み立てておき、入る瞬間に
/// 高さと不透明度だけを動かす。Reduce Motion では高さを動かさない。
struct SpotlightRevealRow<Content: View>: View {
    let isRevealed: Bool
    let reduceMotion: Bool
    let content: () -> Content

    @State private var naturalHeight: CGFloat = 0

    init(
        isRevealed: Bool,
        reduceMotion: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isRevealed = isRevealed
        self.reduceMotion = reduceMotion
        self.content = content
    }

    var body: some View {
        Color.clear
            .frame(height: displayedHeight, alignment: .top)
            .overlay(alignment: .top) {
                content()
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { naturalHeight = proxy.size.height }
                                .onChange(of: proxy.size.height) { _, height in
                                    naturalHeight = height
                                }
                        }
                    }
                    .opacity(isRevealed ? 1 : 0)
                    .animation(RowSpotlightTiming.revealOpacityAnimation, value: isRevealed)
            }
            .clipped()
            .animation(
                reduceMotion ? nil : RowSpotlightTiming.revealHeightAnimation,
                value: isRevealed
            )
    }

    private var displayedHeight: CGFloat {
        isRevealed ? naturalHeight : 0
    }
}

extension View {
    /// 行に一度だけ光り方を付ける（#282）。
    func rowSpotlight(
        _ controller: RowSpotlightController,
        cornerRadius: CGFloat? = nil
    ) -> some View {
        modifier(RowSpotlightModifier(controller: controller, cornerRadius: cornerRadius))
    }

    /// 行の矩形（画面座標）を覚えておく（#282）。
    @ViewBuilder
    func rowSpotlightFrame<Key: Hashable>(
        _ key: Key,
        into store: RowFrameStore<Key>?
    ) -> some View {
        if let store {
            onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                store.update(key, frame: frame)
            }
        } else {
            self
        }
    }
}

// MARK: - List の UIScrollView を自分で動かす（#282 レビュー）

/// SwiftUI の `scrollTo` は指定した時間・カーブを使わないため、
/// `List` の下の `UIScrollView` を CADisplayLink で直接動かす。
@MainActor
final class SpotlightScrollAnimator: NSObject {
    private var displayLink: CADisplayLink?
    private var continuation: CheckedContinuation<Void, Never>?
    private weak var scrollView: UIScrollView?
    private var from: CGFloat = 0
    private var to: CGFloat = 0
    private var duration: TimeInterval = 0
    private var startTime: CFTimeInterval = 0
    private var lastOffset: CGFloat = 0
    private var frameIndex = 0
    private var firstDeltas: [CGFloat] = []
    private var recentDeltas: [CGFloat] = []

    /// 指定した区間を、指定した時間とカーブで動かす。
    func animate(
        scrollView: UIScrollView,
        from: CGFloat,
        to: CGFloat,
        duration: TimeInterval
    ) async {
        stop()
        self.scrollView = scrollView
        self.from = from
        self.to = to
        self.duration = max(0.01, duration)
        // 最初のフレームを t=0 にする（シートの閉じる処理で最初のフレームが遅れても、急に動き出さない）
        self.startTime = 0
        self.lastOffset = from
        self.frameIndex = 0
        self.firstDeltas = []
        self.recentDeltas = []

        #if DEBUG
        NSLog(
            "%@",
            String(
                format: "[SpotlightScroll] start from=%.1f to=%.1f distance=%.1f duration=%.3f",
                Double(from),
                Double(to),
                Double(abs(to - from)),
                duration
            )
        )
        #endif

        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let link = CADisplayLink(target: self, selector: #selector(step(_:)))
            link.add(to: .main, forMode: .common)
            self.displayLink = link
        }
    }

    /// 途中で止める（ユーザー操作・タスクのキャンセル）。
    func stop() {
        finish()
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let scrollView else {
            finish()
            return
        }
        // ユーザーが触ったら、その操作を優先してすぐやめる
        if scrollView.isTracking || scrollView.isDragging {
            finish()
            return
        }

        if startTime == 0 {
            startTime = link.timestamp
        }
        let elapsed = link.timestamp - startTime
        let progress = min(1, max(0, elapsed / duration))
        let eased = SpotlightBezier.value(
            x: progress,
            x1: 0.33, y1: 0,
            x2: 0.15, y2: 1
        )
        let offset = from + (to - from) * CGFloat(eased)
        let delta = offset - lastOffset

        if frameIndex < 6 {
            firstDeltas.append(delta)
        }
        recentDeltas.append(delta)
        if recentDeltas.count > 6 {
            recentDeltas.removeFirst()
        }

        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: offset),
            animated: false
        )

        #if DEBUG
        NSLog(
            "%@",
            String(
                format: "[SpotlightScroll] frame=%d t=%.3f offset=%.1f delta=%.2f",
                frameIndex,
                elapsed,
                Double(offset),
                Double(delta)
            )
        )
        #endif

        lastOffset = offset
        frameIndex += 1

        if progress >= 1 {
            finish()
        }
    }

    private func finish() {
        let wasActive = displayLink != nil || continuation != nil
        displayLink?.invalidate()
        displayLink = nil
        if let continuation {
            self.continuation = nil
            continuation.resume()
        }
        #if DEBUG
        if wasActive, frameIndex > 0 {
            let first = firstDeltas.map { String(format: "%.2f", Double($0)) }.joined(separator: ",")
            let last = recentDeltas.map { String(format: "%.2f", Double($0)) }.joined(separator: ",")
            NSLog(
                "%@",
                String(
                    format: "[SpotlightScroll] done frames=%d elapsed=%.3f first=[%@] last=[%@]",
                    frameIndex,
                    CACurrentMediaTime() - startTime,
                    first,
                    last
                )
            )
        }
        #endif
        scrollView = nil
    }
}

/// cubic-bezier の x から y を求める（CSS の timingCurve と同じ）。
enum SpotlightBezier {
    static func value(
        x: Double,
        x1: Double,
        y1: Double,
        x2: Double,
        y2: Double
    ) -> Double {
        let clampedX = min(1, max(0, x))
        var low = 0.0
        var high = 1.0
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if component(mid, p1: x1, p2: x2) < clampedX {
                low = mid
            } else {
                high = mid
            }
        }
        return component((low + high) / 2, p1: y1, p2: y2)
    }

    private static func component(_ t: Double, p1: Double, p2: Double) -> Double {
        let mt = 1 - t
        return 3 * mt * mt * t * p1 + 3 * mt * t * t * p2 + t * t * t
    }
}

/// `List` の下にある `UIScrollView`（UICollectionView）を見つける（#282 レビュー）。
struct ScrollViewResolver: UIViewRepresentable {
    let onResolve: (UIScrollView?) -> Void

    func makeUIView(context: Context) -> ResolverView {
        let view = ResolverView()
        view.onResolve = onResolve
        return view
    }

    func updateUIView(_ uiView: ResolverView, context: Context) {
        uiView.onResolve = onResolve
        uiView.resolve()
    }

    final class ResolverView: UIView {
        var onResolve: ((UIScrollView?) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            resolve()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            resolve()
        }

        func resolve() {
            var view = superview
            while let current = view {
                if let scrollView = current as? UIScrollView {
                    onResolve?(scrollView)
                    return
                }
                view = current.superview
            }
        }
    }
}
