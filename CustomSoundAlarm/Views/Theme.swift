import SwiftUI

// MARK: - Brand Colors

/// Warm Glow デザインテーマ
/// アプリアイコン（紫グラデ＋白ベル＋オレンジアクセント）の世界観を反映
enum Brand {
    // Deep purple from icon
    static let purple = Color(red: 0.29, green: 0.10, blue: 0.42) // #4A1A6B
    static let purpleLight = Color(red: 0.42, green: 0.25, blue: 0.63) // #6B3FA0

    // Gradients
    static let purpleGradient = LinearGradient(
        colors: [purple, purpleLight],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let warmGoldGradient = LinearGradient(
        colors: [Color.accentColor, Color(red: 1.0, green: 0.65, blue: 0.3)],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let saveButtonGradient = LinearGradient(
        colors: [Color.accentColor, Color(red: 0.95, green: 0.45, blue: 0.2)],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Adaptive Brand Colors (Light/Dark)

extension Color {
    /// Warm-tinted background for list/form screens
    static let warmListBackground = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.12, green: 0.08, blue: 0.18, alpha: 1)
                : UIColor(red: 0.98, green: 0.96, blue: 0.94, alpha: 1)
        }
    )

    /// Card background for alarm rows
    static let warmCardBackground = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.18, green: 0.13, blue: 0.24, alpha: 1)
                : UIColor(red: 1.0, green: 0.98, blue: 0.96, alpha: 1)
        }
    )
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
            MiniWaveformBars(color: .accentColor, barWidth: max(size / 7, 1.5), height: size)
        } else {
            Image(systemName: "music.note")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Brand.purpleLight)
        }
    }
}

/// ミニ波形バー（4本）— カスタムサウンドの視覚的インジケーター
struct MiniWaveformBars: View {
    var color: Color = .accentColor
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
                            colors: [Color.accentColor, Brand.purpleLight],
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
            .foregroundStyle(Brand.purpleLight)
    }
}
