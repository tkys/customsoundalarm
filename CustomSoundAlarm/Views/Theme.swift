import SwiftUI

// MARK: - Brand Colors

/// Warm Glow デザインテーマ
/// アプリアイコン（紫グラデ＋白ベル＋オレンジアクセント）の世界観を反映
enum Brand {
    /// ブランドのオレンジ（AccentColor）。**図形専用**。
    /// 波形・選択中の印・アイコン・タブの選択中・トグルの tint には使うが、
    /// 文字や押せる文字には使わない（#174）。文字は `Color.actionText`。
    static let orange = Color("AccentColor")

    // Deep purple from icon
    static let purple = Color(red: 0.29, green: 0.10, blue: 0.42) // #4A1A6B
    static let purpleLight = Color(red: 0.42, green: 0.25, blue: 0.63) // #6B3FA0
    /// 見出し・ブランドの声（押せない文字）。ライトは #4A1A6B、ダークは読みやすい紫。
    static let heading = Color("BrandHeading")

    // Gradients
    static let purpleGradient = LinearGradient(
        colors: [purple, purpleLight],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 装飾用（図形・アイコン）。文字には使わない。
    static let warmGoldGradient = LinearGradient(
        colors: [orange, Color(red: 1.0, green: 0.65, blue: 0.3)],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// 白文字ボタンの地。開始色・終了色とも白文字と 3:1 以上（#174）。
    static let saveButtonGradient = LinearGradient(
        colors: [Color.actionFillStart, Color.actionFillEnd],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Accent UIColor (#81-2)

extension Brand {
    /// AccentColor アセットを直接解決した UIColor（#81-2）。
    ///
    /// `UIColor(Color.accentColor)` は環境依存の動的な色のため、ビュー階層の外で
    /// 橋渡しするとアセットの値が解決されずシステム既定の青にフォールバックする。
    /// DSWaveformImage の設定色にはこちらを使うこと。
    /// ダークモードは `UITraitCollection` で明示的に解決する。
    static func accentUIColor(dark: Bool) -> UIColor {
        let base = UIColor(named: "AccentColor") ?? .systemOrange
        return base.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        )
    }
}

// MARK: - Adaptive Brand Colors (Light/Dark)

extension Color {
    /// 押せる文字・押せるアイコン（#174）。ライト 4.5:1 以上、ダーク 6.9:1 以上。
    static let actionText = Color("ActionText")
    /// 押せない補足・オフ状態の文字。小さくても 4.5:1 以上（#174）。
    static let textSecondary = Color("TextSecondary")
    /// 白文字ボタンの地（開始色・終了色とも白文字と 3:1 以上・#174）。
    static let actionFillStart = Color("ActionFillStart")
    static let actionFillEnd = Color("ActionFillEnd")

    /// Warm-tinted background for list/form screens
    static let warmListBackground = Color("WarmListBackground")

    /// Card background for alarm rows
    static let warmCardBackground = Color("WarmCardBackground")
}

// MARK: - View Modifiers

/// Warm card-style row background
struct WarmCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .listRowBackground(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.warmCardBackground)
                    .shadow(
                        color: colorScheme == .dark
                            ? Color.black.opacity(0.3)
                            : Color.orange.opacity(0.08),
                        radius: 4, x: 0, y: 2
                    )
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
            )
    }
}

/// Warm list/form background
struct WarmListBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Color.warmListBackground.ignoresSafeArea())
    }
}

extension View {
    func warmCard() -> some View {
        modifier(WarmCardModifier())
    }

    func warmListBackground() -> some View {
        modifier(WarmListBackgroundModifier())
    }
}

// MARK: - Sound Icon

/// Small waveform indicator for sound names
struct SoundIndicator: View {
    var isCustom: Bool = false
    var size: CGFloat = 14

    var body: some View {
        if isCustom {
            MiniWaveformBars(color: Brand.orange, barWidth: max(size / 7, 1.5), height: size)
        } else {
            Image(systemName: "music.note")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Brand.purpleLight)
        }
    }
}

/// ミニ波形バー（4本）— カスタムサウンドの視覚的インジケーター
struct MiniWaveformBars: View {
    var color: Color = Brand.orange
    var barWidth: CGFloat = 2
    var height: CGFloat = 14
    var animated: Bool = false

    private let relativeHeights: [CGFloat] = [0.5, 1.0, 0.75, 0.4]

    var body: some View {
        HStack(spacing: barWidth * 0.75) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                    .fill(color)
                    .frame(width: barWidth, height: height * relativeHeights[i])
            }
        }
        .frame(height: height)
    }
}

/// 空状態用の装飾的サウンドウェーブ
struct SoundWaveDecoration: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let barHeights: [CGFloat] = [20, 35, 50, 65, 50, 35, 20]
        HStack(spacing: 5) {
            ForEach(0..<7, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Brand.orange, Brand.purpleLight],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 8, height: barHeights[i])
                    .opacity(0.5 + Double(i) * 0.07)
            }
        }
    }
}

// MARK: - Section Header Style

struct WarmSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Brand.heading)
    }
}
