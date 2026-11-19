import SwiftUI

/// 切り取り画面の中で、シートを使わずに無音を知らせる（#256）。
struct SilentSoundNoticeView: View {
    let level: SilentSoundLevel
    /// 元ファイル全体が無音。範囲を選び直しても無音なので、別の音だけを促す。
    let isWholeFileSilent: Bool
    let onReselect: () -> Void
    let onOtherSound: () -> Void
    let onUseAnyway: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isWholeFileSilent ? "silent_sound_whole_file_message" : "silent_sound_message")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("silentSound.message")

            if isWholeFileSilent {
                otherSoundButton(lineLimit: nil)
                    .frame(maxWidth: .infinity)
            } else {
                // 両方が1行で横に収まるときだけ横並び。収まらなければ縦に積む（#256 レビュー）。
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        reselectButton(lineLimit: 1)
                        otherSoundButton(lineLimit: 1)
                    }
                    VStack(spacing: 8) {
                        reselectButton(lineLimit: nil)
                            .frame(maxWidth: .infinity)
                        otherSoundButton(lineLimit: nil)
                            .frame(maxWidth: .infinity)
                    }
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

    private func reselectButton(lineLimit: Int?) -> some View {
        Button(action: onReselect) {
            Text("silent_sound_reselect")
                .lineLimit(lineLimit)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("silentSound.reselect")
    }

    private func otherSoundButton(lineLimit: Int?) -> some View {
        Button(action: onOtherSound) {
            Text("silent_sound_other")
                .lineLimit(lineLimit)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("silentSound.other")
    }
}
