import SwiftUI

/// オンボーディング（#98）。場面1〜4。
///
/// 設計原則（docs/onboarding_refresh_instructions.md）:
/// - 本文テキストを置かない（イラスト＋見出し1行で伝える）
/// - ライト表示に固定（イラストが白背景のため・ダークモードでも白）
/// - reduceMotion が true ならアニメーションを省く
struct OnboardingView: View {
    /// 完了時。source は場面4の選択（Phase 2 の暫定では .later）
    let onComplete: (OnboardingSource) -> Void

    @State private var step: OnboardingStep = .intro
    /// 場面2の左→右へ一度だけの塗りアニメーション済みフラグ
    @State private var loopSweepApplied = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // ライト固定・白背景（ダークモードでもオンボは白）
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                illustration
                Spacer(minLength: 0)
                headline
                    .padding(.bottom, 32)
                Spacer(minLength: 0)
                primaryButton
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .preferredColorScheme(.light)
    }

    // MARK: - 場面ごとの部品

    @ViewBuilder
    private var illustration: some View {
        switch step {
        case .intro:
            // 場面1: 朝のベッド（画面の約55%）
            OnboardingIllustration(assetName: "onboarding_hero", aspectRatio: 3.0 / 4.0)
                .frame(maxHeight: UIScreen.main.bounds.height * 0.55)
        case .loop:
            // 場面2: サビのくり返し（色付き部分を左→右へ一度だけ塗る・reduceMotion 時なし）
            OnboardingIllustration(assetName: "onboarding_loop", aspectRatio: 4.0 / 3.0)
                .overlay(alignment: .bottomLeading) {
                    if !reduceMotion {
                        sweepOverlay
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        case .permission, .source:
            // 場面3・4は Phase 3/4 で実装
            OnboardingIllustration(assetName: "onboarding_silent", aspectRatio: 1.0)
        }
    }

    /// 波形の色付き部分を左→右へ一度だけ塗る軽いアニメーション（画像の下部40%）
    private var sweepOverlay: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.accentColor.opacity(0.14))
                .frame(width: loopSweepApplied ? geo.size.width : 0,
                       height: geo.size.height * 0.4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !loopSweepApplied else { return }
            withAnimation(.easeInOut(duration: 1.2)) {
                loopSweepApplied = true
            }
        }
    }

    private var headline: some View {
        Text(headlineKey)
            .font(.system(.title2, design: .rounded).weight(.bold))
            .foregroundStyle(Color.primary)
            .multilineTextAlignment(.center)
    }

    private var headlineKey: LocalizedStringKey {
        switch step {
        case .intro: "onb.hero.title"
        case .loop: "onb.loop.title"
        case .permission: "onb.silent.title"
        case .source: "onb.source.title"
        }
    }

    private var primaryButton: some View {
        Button {
            advance()
        } label: {
            Text("onb.next")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    Capsule().fill(Brand.saveButtonGradient)
                )
        }
    }

    private func advance() {
        switch step {
        case .intro:
            step = .loop
        case .loop:
            // Phase 3 で場面3（許可）へ進める。暫定ではここで完了扱い
            onComplete(.later)
        case .permission, .source:
            // Phase 3/4 で実装
            onComplete(.later)
        }
    }
}

// MARK: - OnboardingIllustration

/// オンボ用イラスト（#98）。
/// 素材（`Assets.xcassets` の imageset）が無い間は、同じ比率の薄いグレーの角丸枠を
/// 表示する（クラッシュ・レイアウト崩れなし）。素材が入ったら差し替え不要で表示される。
struct OnboardingIllustration: View {
    let assetName: String
    /// 幅/高さ（例: 3:4 → 0.75）
    let aspectRatio: CGFloat

    var body: some View {
        if let image = UIImage(named: assetName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(white: 0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color(white: 0.86), lineWidth: 1)
                )
                .aspectRatio(aspectRatio, contentMode: .fit)
        }
    }
}
