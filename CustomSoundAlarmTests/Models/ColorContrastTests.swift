import Testing
import UIKit
@testable import CustomSoundAlarm

/// 配色ルールのコントラスト比（#174）。
///
/// 色アセットの実値から WCAG 2.x の相対輝度を計算し、
/// ライト／ダーク × リスト背景／カード背景の両方で確認する。
/// 旧オレンジ（#FF843B）に戻すと落ちることも陰性確認として持つ。
struct ColorContrastTests {

    // MARK: - Helpers

    private func color(_ name: String, dark: Bool) -> UIColor {
        guard let base = UIColor(named: name) else {
            Issue.record("Color asset not found: \(name)")
            return .magenta
        }
        return base.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        )
    }

    private func luminance(_ color: UIColor) -> Double {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        func linear(_ component: CGFloat) -> Double {
            let value = Double(component)
            return value <= 0.04045
                ? value / 12.92
                : pow((value + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linear(red)
            + 0.7152 * linear(green)
            + 0.0722 * linear(blue)
    }

    private func contrast(_ foreground: UIColor, _ background: UIColor) -> Double {
        let first = luminance(foreground)
        let second = luminance(background)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private func contrast(
        _ foregroundName: String,
        _ backgroundName: String,
        dark: Bool
    ) -> Double {
        contrast(
            color(foregroundName, dark: dark),
            color(backgroundName, dark: dark)
        )
    }

    private var backgrounds: [String] {
        ["WarmListBackground", "WarmCardBackground"]
    }

    // MARK: - Text

    @Test
    func actionTextMeetsFourPointFiveOnWarmBackgrounds() {
        for dark in [false, true] {
            for background in backgrounds {
                let ratio = contrast("ActionText", background, dark: dark)
                #expect(
                    ratio >= 4.5,
                    "ActionText on \(background) (dark: \(dark)) is \(ratio):1"
                )
            }
        }
    }

    @Test
    func secondaryTextMeetsFourPointFiveOnWarmBackgrounds() {
        for dark in [false, true] {
            for background in backgrounds {
                let ratio = contrast("TextSecondary", background, dark: dark)
                #expect(
                    ratio >= 4.5,
                    "TextSecondary on \(background) (dark: \(dark)) is \(ratio):1"
                )
            }
        }
    }

    @Test
    func mutedTextMeetsFourPointFiveAndIsAStepLighterThanSecondary() {
        for dark in [false, true] {
            for background in backgrounds {
                let muted = contrast("TextMuted", background, dark: dark)
                let secondary = contrast("TextSecondary", background, dark: dark)
                #expect(
                    muted >= 4.5,
                    "TextMuted on \(background) (dark: \(dark)) is \(muted):1"
                )
                #expect(
                    muted < secondary,
                    "TextMuted should be lighter than TextSecondary on \(background) (dark: \(dark)): \(muted) vs \(secondary)"
                )
            }
        }
    }

    @Test
    func headingsMeetFourPointFiveOnWarmBackgrounds() {
        for dark in [false, true] {
            for background in backgrounds {
                let ratio = contrast("BrandHeading", background, dark: dark)
                #expect(
                    ratio >= 4.5,
                    "BrandHeading on \(background) (dark: \(dark)) is \(ratio):1"
                )
            }
        }
    }

    // MARK: - White text on filled buttons

    @Test
    func whiteTextOnActionFillMeetsThreeToOneAtBothStops() {
        for fill in ["ActionFillStart", "ActionFillEnd"] {
            for dark in [false, true] {
                let ratio = contrast(.white, color(fill, dark: dark))
                #expect(
                    ratio >= 3.0,
                    "white on \(fill) (dark: \(dark)) is \(ratio):1"
                )
            }
        }
    }

    @Test
    func whiteTextOnActionFillEndAlsoSupportsSmallBadges() {
        for dark in [false, true] {
            let ratio = contrast(.white, color("ActionFillEnd", dark: dark))
            #expect(ratio >= 4.5, "white on ActionFillEnd is \(ratio):1")
        }
    }

    // MARK: - Negative check

    @Test
    func oldBrandOrangeStillFailsTextAndButtonContrast() {
        // #174 以前のオレンジ。文字・白文字ボタンに戻したら落ちることを示す。
        let oldOrange = UIColor(
            red: 1.0,
            green: 0.518,
            blue: 0.231,
            alpha: 1
        )

        for background in backgrounds {
            let ratio = contrast(oldOrange, color(background, dark: false))
            #expect(
                ratio < 4.5,
                "old orange on \(background) unexpectedly passes: \(ratio):1"
            )
        }

        let buttonRatio = contrast(.white, oldOrange)
        #expect(
            buttonRatio < 3.0,
            "old orange with white text unexpectedly passes: \(buttonRatio):1"
        )
    }
}
