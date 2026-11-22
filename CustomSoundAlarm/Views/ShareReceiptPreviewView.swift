#if DEBUG
import SwiftUI

/// 共有直後の受け取り画面のプレビュー（#239）。
/// ShareExtension は UI テストから単体起動できないため、同じ文言・フォント・色で
/// スクリーンショットを撮るための DEBUG 専用画面。
struct ShareReceiptPreviewView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("received_title")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("received_detail")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .accessibilityIdentifier("shareReceipt.root")
    }
}
#endif
