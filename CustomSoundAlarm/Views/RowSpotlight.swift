import SwiftUI

/// 行を一度だけ静かに光らせる共通部品（#282）。
///
/// アラームの新規作成・時刻の編集・共有後の着地（#246）・連続作成（#198）で使う。
/// 時間とカーブはここにまとめ、行には光らせる部品を付けるだけで使える。
enum RowSpotlightTiming {
    /// 立ち上がり（ease-out）
    static let rise: TimeInterval = 0.2
    /// 光ったまま保つ
    static let hold: TimeInterval = 0.6
    /// 消え方（ease-in-out）
    static let fade: TimeInterval = 0.9
    /// スクロールの所要時間。距離が長くても同じ時間でゆっくり止まる
    static let scroll: TimeInterval = 0.45
    /// スクロールがあるときは、止まり際（8割）から立ち上がりを始める
    static let riseDuringScroll: Double = 0.8

    static var riseDelayWhenScrolling: TimeInterval { scroll * riseDuringScroll }

    /// 行の背景に重ねるアクセントの濃さ（約15%）
    static let accentOpacity: Double = 0.15
    /// スクロール後の行の位置（画面の中ほど・やや上）
    static let scrollAnchor = UnitPoint(x: 0.5, y: 0.45)

    static let riseAnimation: Animation = .easeOut(duration: rise)
    static let fadeAnimation: Animation = .easeInOut(duration: fade)
    static let scrollAnimation: Animation = .smooth(duration: scroll)
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
    /// - Parameter startDelay: スクロールがあるときに止まり際まで待つ秒数。
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
