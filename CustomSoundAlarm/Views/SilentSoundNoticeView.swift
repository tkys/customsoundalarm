import SwiftUI

/// 切り取り画面の中で、シートを使わずに無音を知らせる（#256）。
struct SilentSoundNoticeView: View {
    let level: SilentSoundLevel
    let onReselect: () -> Void
    let onOtherSound: () -> Void
    let onUseAnyway: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("silent_sound_message")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("silentSound.message")

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    reselectButton.frame(maxWidth: .infinity)
                    otherSoundButton.frame(maxWidth: .infinity)
                }
            } else {
                HStack(spacing: 8) {
                    reselectButton
                    otherSoundButton
                }
            }

            if level == .veryQuiet {
                Button("silent_sound_use_anyway", action: onUseAnyway)
                    .buttonStyle(.borderless)
                    .font(.subheadline.weight(.medium))
                    .tint(Color.actionText)
                    .accessibilityIdentifier("silentSound.useAnyway")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.warmCardBackground)
        )
    }

    private var reselectButton: some View {
        Button(action: onReselect) {
            Text("silent_sound_reselect")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("silentSound.reselect")
    }

    private var otherSoundButton: some View {
        Button(action: onOtherSound) {
            Text("silent_sound_other")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("silentSound.other")
    }
}
