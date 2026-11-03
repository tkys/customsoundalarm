import SwiftUI

/// 「PRO・先行公開中」の小さなバッジ（#151 / #160）。
struct EarlyAccessBadge: View {
    var body: some View {
        Text("pro_early_access")
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.orange.opacity(0.16))
            )
            .foregroundStyle(Color.orange)
            .accessibilityIdentifier("playlist.earlyAccessBadge")
    }
}
