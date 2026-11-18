import SwiftUI

/// 許可が拒否済みのときに、設定アプリへ移る前に出すシート（#239）。
struct PermissionSettingsSheet: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 12) {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(Color.actionText)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text("alarm_title")
                    .font(.body)
                Spacer()
                Toggle("", isOn: .constant(true))
                    .labelsHidden()
                    .disabled(true)
                    .tint(.green)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .accessibilityIdentifier("permissionSettings.row")

            Text("permission_settings_hint")
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("permissionSettings.hint")

            Button(action: onOpenSettings) {
                Text("permission_settings_open")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color.actionFillEnd)
            .accessibilityIdentifier("permissionSettings.open")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
