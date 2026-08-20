import SwiftUI

// MARK: - フリップ時計（Pro・#72 Phase2）

/// 中央の水平分割線と2枚パネルの構造のみのフリップ時計。
/// - 上フラップに時・下フラップに分を表示（フラップの角丸は回転面の表現のみ）
/// - テクスチャ・ネジ等の装飾は入れない（暗所の可読性と色替え追従のため）
/// - 前景は「単色＋不透明度のみ」・Canvas 描画・色固定なし（全フェイス共通制約）
/// - 秒表示はフリップの構造上持たない（HH:MM のみ）
struct FlipClockFaceView: View {
    let date: Date
    let theme: BedsideClockLogic.ColorTheme
    let fontScale: Double

    var body: some View {
        GeometryReader { geo in
            let panelHeight = min(geo.size.width * 0.8, geo.size.height * 0.72) * clampedScale
            let panelWidth = panelHeight * 1.9
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2

            Canvas { context, _ in
                drawPanel(context: context, x: cx - panelWidth / 2, y: cy - panelHeight / 2,
                          width: panelWidth, height: panelHeight, radius: panelHeight * 0.05,
                          roundedBottom: true)
                drawPanel(context: context, x: cx - panelWidth / 2, y: cy,
                          width: panelWidth, height: panelHeight / 2, radius: panelHeight * 0.05,
                          roundedTop: true)

                // 中央の水平分割線
                var line = Path()
                line.move(to: CGPoint(x: cx - panelWidth / 2 + panelHeight * 0.06, y: cy))
                line.addLine(to: CGPoint(x: cx + panelWidth / 2 - panelHeight * 0.06, y: cy))
                context.stroke(line, with: .color(theme.clockColor.opacity(0.5)), lineWidth: 1.5)

                let hourText = Self.hourText(for: date)
                let minuteText = Self.minuteText(for: date)
                let digitSize = panelHeight * 0.4
                drawText(context: context, text: hourText, center: CGPoint(x: cx, y: cy - panelHeight * 0.25), size: digitSize)
                drawText(context: context, text: minuteText, center: CGPoint(x: cx, y: cy + panelHeight * 0.25), size: digitSize)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityLabel("Flip clock showing \(Self.timeString(for: date))")
    }

    /// 文字サイズ設定（0.7〜1.5）に追従する
    private var clampedScale: Double {
        min(max(fontScale, 0.7), 1.5)
    }

    private func drawPanel(context: GraphicsContext, x: CGFloat, y: CGFloat,
                           width: CGFloat, height: CGFloat, radius: CGFloat,
                           roundedBottom: Bool = false, roundedTop: Bool = false) {
        var rect = Path(roundedRect: CGRect(x: x, y: y, width: width, height: height),
                        cornerRadius: radius,
                        style: .continuous)
        if roundedBottom {
            rect = Path(roundedRect: CGRect(x: x, y: y, width: width, height: height),
                        cornerRadius: radius,
                        style: .continuous)
            // 下フラップの角丸は下側のみ
            let flap = Path { p in
                p.move(to: CGPoint(x: x, y: y))
                p.addLine(to: CGPoint(x: x + width, y: y))
                p.addLine(to: CGPoint(x: x + width, y: y + height - radius))
                p.addArc(tangent1End: CGPoint(x: x + width, y: y + height),
                         tangent2End: CGPoint(x: x + width - radius, y: y + height), radius: radius)
                p.addArc(tangent1End: CGPoint(x: x, y: y + height),
                         tangent2End: CGPoint(x: x, y: y + height - radius), radius: radius)
                p.closeSubpath()
            }
            context.fill(flap, with: .color(theme.clockColor.opacity(0.05)))
            context.stroke(flap, with: .color(theme.clockColor.opacity(0.25)), lineWidth: 1)
            return
        }
        if roundedTop {
            let flap = Path { p in
                p.move(to: CGPoint(x: x + radius, y: y))
                p.addArc(tangent1End: CGPoint(x: x, y: y), tangent2End: CGPoint(x: x, y: y + radius), radius: radius)
                p.addArc(tangent1End: CGPoint(x: x, y: y + height),
                         tangent2End: CGPoint(x: x + width, y: y + height), radius: radius)
                p.addLine(to: CGPoint(x: x + width, y: y + radius))
                p.addArc(tangent1End: CGPoint(x: x + width, y: y), tangent2End: CGPoint(x: x + width - radius, y: y), radius: radius)
                p.closeSubpath()
            }
            context.fill(flap, with: .color(theme.clockColor.opacity(0.05)))
            context.stroke(flap, with: .color(theme.clockColor.opacity(0.25)), lineWidth: 1)
            return
        }
        context.fill(rect, with: .color(theme.clockColor.opacity(0.05)))
        context.stroke(rect, with: .color(theme.clockColor.opacity(0.25)), lineWidth: 1)
    }

    private func drawText(context: GraphicsContext, text: String, center: CGPoint, size: CGFloat) {
        let t = Text(text)
            .font(.system(size: size, weight: .light, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(theme.clockColor)
        context.draw(t, at: center, anchor: .center)
    }

    // MARK: - 時刻

    private static func hourText(for date: Date) -> String {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        if BedsideClockLogic.is24HourFormat(for: date) {
            return String(format: "%02d", hour)
        }
        return String(hour % 12 == 0 ? 12 : hour % 12)
    }

    private static func minuteText(for date: Date) -> String {
        String(format: "%02d", Calendar.current.component(.minute, from: date))
    }

    private static func timeString(for date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }
}

// MARK: - 7セグLED（Pro・#72 Phase2）

/// 7セグメントLEDのデジタル時計。
/// 肝は「消灯セグメントを薄い不透明度（0.12）で表示する」こと。
/// 点灯セグメントだけ描くと安っぽくなる。hexagon 形状（平行四辺形）で描画。
struct SevenSegmentFaceView: View {
    let date: Date
    let theme: BedsideClockLogic.ColorTheme
    let showSeconds: Bool
    let fontScale: Double

    /// 消灯セグメントの不透明度（本物らしさの肝）
    private static let offOpacity = 0.12

    var body: some View {
        GeometryReader { geo in
            let is24 = BedsideClockLogic.is24HourFormat(for: date)
            let cal = Calendar.current
            let hour = cal.component(.hour, from: date)
            let minute = cal.component(.minute, from: date)
            let second = cal.component(.second, from: date)
            let hourDigits: [Int] = Self.hourDigits(for: hour, is24: is24)
            let minuteDigits = [minute / 10, minute % 10]
            let secondDigits = [second / 10, second % 10]

            // レイアウト: HH:MM（+秒行）。桁幅から全体を決める
            let availW = geo.size.width * 0.9 * clampedScale
            let availH = geo.size.height * (showSeconds ? 0.62 : 0.52) * clampedScale
            let gap = min(availW, availH) * 0.02
            let colonW = min(availW, availH) * 0.06
            let digitW = (availW - gap * 2 - colonW) / 4
            let digitH = digitW * 1.7
            let scale = min(1.0, availH / (digitH + (showSeconds ? digitH * 0.5 : 0) + gap))
            let w = digitW * scale
            let h = digitH * scale
            let mainW = w * 4 + colonW + gap * 2
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2
            let totalH = showSeconds ? h * 1.5 + gap : h
            let mainTop = cy - totalH / 2

            Canvas { context, _ in
                let startX = cx - mainW / 2
                drawDigits(context: context, digits: hourDigits, startX: startX, y: mainTop, w: w, h: h, gap: gap)
                drawColon(context: context, x: startX + w * 2 + gap, y: mainTop, h: h, w: colonW, blinkOn: !showSeconds || second % 2 == 0)
                drawDigits(context: context, digits: minuteDigits, startX: startX + w * 2 + colonW + gap * 2, y: mainTop, w: w, h: h, gap: gap)
                // 秒行
                if showSeconds {
                    drawDigits(context: context, digits: secondDigits, startX: cx - (w * 0.5 + gap / 2), y: mainTop + h + gap, w: w * 0.5, h: h * 0.5, gap: gap)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityLabel("Seven segment clock showing \(Self.timeString(for: date))")
    }

    /// 時を2桁配列で返す（12時制は先頭桁を消灯 = -1 にする）
    private static func hourDigits(for hour: Int, is24: Bool) -> [Int] {
        if is24 {
            return [hour / 10, hour % 10]
        }
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return h12 < 10 ? [-1, h12] : [h12 / 10, h12 % 10]
    }

    private var clampedScale: Double {
        min(max(fontScale, 0.7), 1.5)
    }

    // MARK: - セグメント描画

    private func drawDigits(context: GraphicsContext, digits: [Int], startX: CGFloat,
                            y: CGFloat, w: CGFloat, h: CGFloat, gap: CGFloat) {
        for (i, digit) in digits.enumerated() {
            let x = startX + CGFloat(i) * (w + gap)
            drawDigit(context: context, digit: digit, x: x, y: y, w: w, h: h)
        }
    }

    private func drawColon(context: GraphicsContext, x: CGFloat, y: CGFloat, h: CGFloat, w: CGFloat, blinkOn: Bool) {
        guard blinkOn else { return }
        let dot = w * 0.5
        let dotY1 = y + h * 0.3
        let dotY2 = y + h * 0.7
        context.fill(
            Path(ellipseIn: CGRect(x: x, y: dotY1, width: dot, height: dot)),
            with: .color(theme.clockColor)
        )
        context.fill(
            Path(ellipseIn: CGRect(x: x, y: dotY2, width: dot, height: dot)),
            with: .color(theme.clockColor)
        )
    }

    /// 1桁を描画する。消灯セグメントは薄く・点灯セグメントはテーマ色で
    private func drawDigit(context: GraphicsContext, digit: Int, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        let mask = Self.segmentMask(for: digit)
        let on = theme.clockColor
        let off = theme.clockColor.opacity(Self.offOpacity)
        let t = w * 0.19          // セグメントの太さ
        let s = w * 0.14          // hexagon のスラント
        let m = w * 0.06          // セグメント間のマージン

        // 水平セグメント（平行四辺形: 左右の辺がスラント）
        func horizontal(_ y1: CGFloat, _ y2: CGFloat, _ seg: Int) {
            let p1 = CGPoint(x: x + s + m, y: y + y1)
            let p2 = CGPoint(x: x + w - s - m, y: y + y1)
            let p3 = CGPoint(x: x + w - s - m, y: y + y2)
            let p4 = CGPoint(x: x + s + m, y: y + y2)
            var path = Path()
            path.move(to: p1)
            path.addLine(to: p2)
            path.addLine(to: p3)
            path.addLine(to: p4)
            path.closeSubpath()
            context.fill(path, with: .color(mask & seg != 0 ? on : off))
        }

        // 垂直セグメント（平行四辺形: 上下の辺がスラント）
        func vertical(_ x1: CGFloat, _ x2: CGFloat, _ y1: CGFloat, _ y2: CGFloat, _ seg: Int) {
            let p1 = CGPoint(x: x + x1, y: y + y1 + s + m)
            let p2 = CGPoint(x: x + x2, y: y + y1 + m)
            let p3 = CGPoint(x: x + x2, y: y + y2 - m)
            let p4 = CGPoint(x: x + x1, y: y + y2 - s - m)
            var path = Path()
            path.move(to: p1)
            path.addLine(to: p2)
            path.addLine(to: p3)
            path.addLine(to: p4)
            path.closeSubpath()
            context.fill(path, with: .color(mask & seg != 0 ? on : off))
        }

        // a: 上 / b: 右上 / c: 右下 / d: 下 / e: 左下 / f: 左上 / g: 中央
        horizontal(0, t, 0b0000001)
        vertical(w - t, w, s, h / 2 - m, 0b0000010)
        vertical(w - t, w, h / 2 + m, h - s, 0b0000100)
        horizontal(h - t, h, 0b0001000)
        vertical(0, t, h / 2 + m, h - s, 0b0010000)
        vertical(0, t, s, h / 2 - m, 0b0100000)
        horizontal(h / 2 - t / 2, h / 2 + t / 2, 0b1000000)
    }

    /// 桁 → 点灯セグメント集合（a=1, b=2, c=4, d=8, e=16, f=32, g=64）
    private static func segmentMask(for digit: Int) -> Int {
        switch digit {
        case 0: 0b0111111 // a,b,c,d,e,f
        case 1: 0b0000110 // b,c
        case 2: 0b1011011 // a,b,g,e,d
        case 3: 0b1001111 // a,b,g,c,d
        case 4: 0b1100110 // f,g,b,c
        case 5: 0b1101101 // a,f,g,c,d
        case 6: 0b1111101 // a,f,g,e,c,d
        case 7: 0b0000111 // a,b,c
        case 8: 0b1111111 // 全て
        case 9: 0b1111011 // a,b,c,d,f,g
        default: 0
        }
    }

    private static func timeString(for date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .medium
        f.dateStyle = .none
        return f.string(from: date)
    }
}

// MARK: - ドットマトリクス（Pro・#72 Phase2）

/// ドットマトリクス時計。時と分を積み上げ配置（時が上・分が下）。
/// ドットの粒を明示的に円で描く（粒がくっつかないようドット径の35%の隙間を開ける）。
struct DotMatrixFaceView: View {
    let date: Date
    let theme: BedsideClockLogic.ColorTheme
    let showSeconds: Bool
    let fontScale: Double

    var body: some View {
        GeometryReader { geo in
            let cal = Calendar.current
            let hour = cal.component(.hour, from: date)
            let minute = cal.component(.minute, from: date)
            let second = cal.component(.second, from: date)
            let is24 = BedsideClockLogic.is24HourFormat(for: date)
            let hourDigits: [Int] = Self.hourDigits(for: hour, is24: is24)

            // 積み上げ行: 時 / 分 /（秒）
            let rows: [[Int]] = showSeconds
                ? [hourDigits, [minute / 10, minute % 10], [second / 10, second % 10]]
                : [hourDigits, [minute / 10, minute % 10]]

            let glyphCols = 5 * 2 + 1 // 2桁 + 隙間1列
            let glyphRows = 7
            let availW = geo.size.width * 0.92 * clampedScale
            let availH = geo.size.height * (showSeconds ? 0.66 : 0.5) * clampedScale
            let spacing = 1.35
            let dotSize = min(availW / (CGFloat(glyphCols) * spacing - 0.35),
                              availH / (CGFloat(rows.count * glyphRows) * spacing - 0.35))
            let rowHeight = dotSize * (spacing * CGFloat(glyphRows) - 0.35)
            let cx = geo.size.width / 2

            Canvas { context, _ in
                let totalH = rowHeight * CGFloat(rows.count)
                var y = geo.size.height / 2 - totalH / 2
                for row in rows {
                    let rowW = dotSize * (CGFloat(5 * row.count + (row.count - 1)) * spacing - 0.35)
                    let rowX = cx - rowW / 2
                    drawGlyphs(context: context, digits: row, startX: rowX, y: y, dotSize: dotSize, spacing: spacing)
                    y += rowHeight
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityLabel("Dot matrix clock showing \(Self.timeString(for: date))")
    }

    /// 時を2桁配列で返す（12時制は先頭桁を消灯 = -1 にする）
    private static func hourDigits(for hour: Int, is24: Bool) -> [Int] {
        if is24 {
            return [hour / 10, hour % 10]
        }
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return h12 < 10 ? [-1, h12] : [h12 / 10, h12 % 10]
    }

    private var clampedScale: Double {
        min(max(fontScale, 0.7), 1.5)
    }

    private func drawGlyphs(context: GraphicsContext, digits: [Int], startX: CGFloat,
                            y: CGFloat, dotSize: CGFloat, spacing: CGFloat) {
        for (i, digit) in digits.enumerated() {
            let gx = startX + CGFloat(i) * (5 * spacing + 0.65) * dotSize
            let glyph = Self.glyph(for: digit)
            for (row, bits) in glyph.enumerated() {
                for col in 0..<5 where bits & (1 << (4 - col)) != 0 {
                    let px = gx + CGFloat(col) * spacing * dotSize + dotSize * 0.5
                    let py = y + CGFloat(row) * spacing * dotSize + dotSize * 0.5
                    let d = dotSize
                    context.fill(
                        Path(ellipseIn: CGRect(x: px - d / 2, y: py - d / 2, width: d, height: d)),
                        with: .color(theme.clockColor)
                    )
                }
            }
        }
    }

    /// 5×7 ドットグリフ（最下位ビットが右端）
    private static func glyph(for digit: Int) -> [Int] {
        switch digit {
        case 0: [0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110]
        case 1: [0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110]
        case 2: [0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111]
        case 3: [0b11111, 0b00010, 0b00100, 0b00010, 0b00001, 0b10001, 0b01110]
        case 4: [0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010]
        case 5: [0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110]
        case 6: [0b00110, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110]
        case 7: [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000]
        case 8: [0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110]
        case 9: [0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b01100]
        default: []
        }
    }

    private static func timeString(for date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .medium
        f.dateStyle = .none
        return f.string(from: date)
    }
}