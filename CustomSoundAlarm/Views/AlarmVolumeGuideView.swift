import SwiftUI

/// アラームの音量の案内（#121）。
/// 設定 → サウンドと触覚 →「着信音と通知音」のスライダーを画像付きで案内する。
/// 入口（「今すぐ鳴らす」の下・音の大きさの下）は #122 で付ける。
struct AlarmVolumeGuideView: View {
    let source: VolumeGuideSource

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(VolumeGuideImage.imageName(for: Locale.current))
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        // 画像名を読み上げさせない
                        .accessibilityLabel(Text("volume_guide_image_label"))
                        .accessibilityIdentifier("volumeGuide.image")

                    stepRow(number: 1, text: "volume_guide_step1")
                        .accessibilityIdentifier("volumeGuide.step1")
                    stepRow(number: 2, text: "volume_guide_step2")
                        .accessibilityIdentifier("volumeGuide.step2")

                    warning
                }
                .padding(20)
            }
            .background(Color.warmListBackground.ignoresSafeArea())
            .navigationTitle(String(localized: "volume_guide_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("close") { dismiss() }
                        .accessibilityIdentifier("volumeGuide.close")
                }
            }
        }
        .accessibilityIdentifier("volumeGuide.root")
        .onAppear {
            AnalyticsService.shared.capture(.volumeGuideOpened(from: source))
        }
    }

    private func stepRow(number: Int, text: String.LocalizationValue) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                // 白はアクセント色の上で 2.4:1 と読みにくいため黒（8.6:1）
                .foregroundStyle(.black)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor))
                .accessibilityHidden(true)

            Text(String(localized: text))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var warning: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("volume_guide_warning")
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .accessibilityIdentifier("volumeGuide.warning")
    }
}
