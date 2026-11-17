import SwiftUI

/// プレイリストの解放シート（#216）。
/// アイコン＋タイトル＋作成ボタンだけ。本文・PRO・先行公開の表示は出さない。
struct PlaylistUnlockSheet: View {
    let onCreate: () -> Void
    let onLater: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var artScale: CGFloat = 0.6
    @State private var artOpacity: Double = 0
    @State private var feedbackTrigger = 0
    @State private var didAnimate = false

    private var isAccessibilitySize: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        VStack(spacing: isAccessibilitySize ? 16 : 20) {
            Spacer(minLength: isAccessibilitySize ? 0 : 8)

            Image("unlock_playlist")
                .resizable()
                .scaledToFit()
                .frame(height: isAccessibilitySize ? 160 : 220)
                .scaleEffect(reduceMotion ? 1 : artScale)
                .opacity(artOpacity)
                .accessibilityHidden(true)

            Text("playlist_unlock_title")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("playlistUnlock.title")

            Button(action: onCreate) {
                Text("playlist_unlock_create")
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color.actionFillEnd)
            .accessibilityIdentifier("playlistUnlock.create")

            Button("playlist_unlock_later", action: onLater)
                .buttonStyle(.plain)
                .accessibilityIdentifier("playlistUnlock.later")

            Spacer(minLength: isAccessibilitySize ? 0 : 8)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .sensoryFeedback(.success, trigger: feedbackTrigger)
        .onAppear {
            guard !didAnimate else { return }
            didAnimate = true
            feedbackTrigger += 1
            if reduceMotion {
                // 視差効果を減らす: 拡大せずフェードだけ
                withAnimation(.easeOut(duration: 0.25)) {
                    artOpacity = 1
                }
            } else {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    artScale = 1.0
                    artOpacity = 1
                }
            }
        }
    }
}
