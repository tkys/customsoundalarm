import SwiftUI

/// アップデート必須／おすすめの案内（#116）。
/// 必須は閉じるボタンを持たず、おすすめだけ「あとで」で閉じられる。
struct UpdatePromptView: View {
    let prompt: UpdatePrompt
    let onUpdate: () -> Void
    let onLater: (() -> Void)?

    @Environment(\.openURL) private var openURL

    private var isRequired: Bool { prompt.kind == .required }

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            Image(systemName: isRequired ? "exclamationmark.triangle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(isRequired ? AnyShapeStyle(.orange) : AnyShapeStyle(Color.accentColor))

            Text(isRequired ? "update_required_title" : "update_recommended_title")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier(isRequired ? "updatePrompt.required" : "updatePrompt.recommended")

            if isRequired {
                Text("update_required_message")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                openURL(UpdatePrompt.appStoreURL)
                onUpdate()
            } label: {
                Text("update_button")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("updatePrompt.updateButton")

            if let onLater {
                Button(action: onLater) {
                    Text("update_later")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("updatePrompt.laterButton")
            }

            Spacer(minLength: 0)
        }
        .padding(28)
        .interactiveDismissDisabled(isRequired)
    }
}
