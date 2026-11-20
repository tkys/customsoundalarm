import SwiftUI

/// 「PRO・いまは使えます」の小さなバッジ（#151 / #160 / #262）。
struct EarlyAccessBadge: View {
    var accessibilityIdentifier: String = "playlist.earlyAccessBadge"

    var body: some View {
        Text("pro_early_access")
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.actionFillEnd)
            )
            .foregroundStyle(.white)
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}
