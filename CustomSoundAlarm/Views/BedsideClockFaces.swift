import SwiftUI

// MARK: - アナログフェイス（無料・#72 Phase1）

/// 極限までミニマルなアナログフェイス。
/// - 数字は「12」のみ・目盛りは細く控えめ・針は細身の剣型
/// - 針は1本（分針）だけアクセント色（テーマの色相を最大不透明度で使用）、他は単色＋低不透明度
/// - 前景は「単色＋不透明度のみ」で階調を作る（スタイル×カラーの二軸設計を壊さない）
/// - Canvas / GraphicsContext 描画（画像アセット不使用）。文字サイズ変更・回転・焼き付きオフセットに追従
struct AnalogClockFaceView: View {
    let date: Date
    let theme: BedsideClockLogic.ColorTheme
    let showSeconds: Bool
    let fontScale: Double

    var body: some View {
        GeometryReader { geo in
            let diameter = min(geo.size.width, geo.size.height) * 0.9 * clampedScale
            let radius = diameter / 2
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2

            Canvas { context, _ in
                drawFace(context: context, cx: cx, cy: cy, radius: radius)
                drawHands(context: context, cx: cx, cy: cy, radius: radius)
            }
            .frame(width: diameter, height: diameter)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityLabel("Analog clock showing \(Self.timeString(for: date))")
    }

    /// 文字サイズ設定（0.7〜1.5）に追従する。フェイス側に色を固定しない
    private var clampedScale: Double {
        min(max(fontScale, 0.7), 1.5)
    }

    // MARK: - 盤面

    private func drawFace(context: GraphicsContext, cx: CGFloat, cy: CGFloat, radius: CGFloat) {
        // 薄い外枠
        let ringRect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
        context.stroke(
            Path(ellipseIn: ringRect),
            with: .color(theme.clockColor.opacity(0.25)),
            lineWidth: 1
        )

        // 目盛り: 時目盛りはやや濃く・分目盛りは極薄く
        for i in 0..<60 {
            let angle = Double(i) / 60.0 * 2.0 * Double.pi - Double.pi / 2.0
            let cosA = Foundation.cos(angle)
            let sinA = Foundation.sin(angle)
            let isHour = i % 5 == 0
            let inner = radius * (isHour ? 0.80 : 0.90)
            let outer = radius * 0.94
            var path = Path()
            path.move(to: CGPoint(x: cx + cosA * inner, y: cy + sinA * inner))
            path.addLine(to: CGPoint(x: cx + cosA * outer, y: cy + sinA * outer))
            context.stroke(
                path,
                with: .color(theme.clockColor.opacity(isHour ? 0.4 : 0.12)),
                lineWidth: isHour ? 1.5 : 0.5
            )
        }

        // 「12」のみ
        let twelve = Text("12")
            .font(.system(size: radius * 0.26, weight: .light, design: .default))
            .foregroundStyle(theme.clockColor)
        context.draw(
            twelve,
            at: CGPoint(x: cx, y: cy - radius * 0.72),
            anchor: .center
        )
    }

    // MARK: - 針

    private func drawHands(context: GraphicsContext, cx: CGFloat, cy: CGFloat, radius: CGFloat) {
        let cal = Calendar.current
        let sec = Double(cal.component(.second, from: date))
        let min = Double(cal.component(.minute, from: date)) + sec / 60.0
        let hr = Double(cal.component(.hour, from: date)).truncatingRemainder(dividingBy: 12) + min / 60.0

        // 時針: 単色・低不透明度
        drawSwordHand(
            context: context, cx: cx, cy: cy,
            angle: hr / 12.0 * 2.0 * Double.pi - Double.pi / 2.0,
            length: radius * 0.42, baseWidth: radius * 0.055, tail: radius * 0.07,
            color: theme.clockColor.opacity(0.5)
        )

        // 分針: アクセント（テーマの色相を最大不透明度で・1本だけ）
        drawSwordHand(
            context: context, cx: cx, cy: cy,
            angle: min / 60.0 * 2.0 * Double.pi - Double.pi / 2.0,
            length: radius * 0.62, baseWidth: radius * 0.042, tail: radius * 0.09,
            color: theme.accentColor
        )

        // 秒針: 表示設定時のみ・極細・単色
        if showSeconds {
            let secAngle = sec / 60.0 * 2.0 * Double.pi - Double.pi / 2.0
            let cosA = Foundation.cos(secAngle)
            let sinA = Foundation.sin(secAngle)
            var path = Path()
            path.move(to: CGPoint(x: cx - cosA * radius * 0.12, y: cy - sinA * radius * 0.12))
            path.addLine(to: CGPoint(x: cx + cosA * radius * 0.68, y: cy + sinA * radius * 0.68))
            context.stroke(
                path,
                with: .color(theme.clockColor.opacity(0.4)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
            )
        }

        // センター
        let dotR = radius * 0.03
        context.fill(
            Path(ellipseIn: CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2)),
            with: .color(theme.clockColor.opacity(0.8))
        )
    }

    /// 細身の剣型針（先端に向かって先細る三角形）を描く
    private func drawSwordHand(
        context: GraphicsContext, cx: CGFloat, cy: CGFloat,
        angle: Double, length: CGFloat, baseWidth: CGFloat, tail: CGFloat,
        color: Color
    ) {
        let cosA = Foundation.cos(angle)
        let sinA = Foundation.sin(angle)
        // 針に直交する方向（幅の基準）
        let px = -sinA
        let py = cosA

        let tip = CGPoint(x: cx + cosA * length, y: cy + sinA * length)
        let baseL = CGPoint(x: cx - cosA * tail + px * baseWidth / 2, y: cy - sinA * tail + py * baseWidth / 2)
        let baseR = CGPoint(x: cx - cosA * tail - px * baseWidth / 2, y: cy - sinA * tail - py * baseWidth / 2)

        var path = Path()
        path.move(to: baseL)
        path.addLine(to: baseR)
        path.addLine(to: tip)
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }

    private static func timeString(for date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }
}

// MARK: - ワードクロック（無料・#72 Phase1）

/// 「よる 10じ 20ふん」のように文字で時刻を表すワードクロック。
/// 該当語だけ通常の不透明度で点灯し、非該当語は薄く残す（点灯/消灯の表現）。
/// 5分刻み（:00 は「ちょうど」）。日本語・英語の両方に対応（Localizable.strings 経由）。
struct WordClockView: View {
    let date: Date
    let theme: BedsideClockLogic.ColorTheme
    let fontScale: Double
    let visibleElementCount: Int

    var body: some View {
        let cal = Calendar.current
        let hourIndex = WordClockLogic.hourIndex(hour: cal.component(.hour, from: date))
        let minuteIndex = WordClockLogic.minuteIndex(minute: cal.component(.minute, from: date))
        let baseSize = BedsideClockLogic.clockFontSize(visibleElementCount: visibleElementCount, fontScale: fontScale)

        VStack(spacing: baseSize * 0.16) {
            wordRow(words: [String(localized: "word_clock_night")], litIndices: [0], fontSize: baseSize * 0.26)
            wordRow(words: (1...6).map { String(localized: String.LocalizationValue("word_clock_hour_\($0)")) },
                    litIndices: [hourIndex], fontSize: baseSize * 0.34)
            wordRow(words: (7...12).map { String(localized: String.LocalizationValue("word_clock_hour_\($0)")) },
                    litIndices: [hourIndex], fontSize: baseSize * 0.34)
            wordRow(words: (0...5).map { String(localized: String.LocalizationValue("word_clock_minute_\($0)")) },
                    litIndices: [minuteIndex], fontSize: baseSize * 0.30)
            wordRow(words: (6...11).map { String(localized: String.LocalizationValue("word_clock_minute_\($0)")) },
                    litIndices: [minuteIndex], fontSize: baseSize * 0.30)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityString(for: date))
    }

    /// 1行分の語を表示。litIndices に含まれる語だけ点灯し、他は薄く残す
    private func wordRow(words: [String], litIndices: [Int], fontSize: CGFloat) -> some View {
        HStack(spacing: fontSize * 0.35) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Text(word)
                    .font(.system(size: fontSize, weight: .light, design: .default))
                    .foregroundStyle(litIndices.contains(index) ? theme.clockColor : theme.clockColor.opacity(0.15))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
    }

    private static func accessibilityString(for date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }
}