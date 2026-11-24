import SwiftUI

/// 端末の書き方で時刻を出し、AM／PM を数字より小さく並べる（#283）。
struct AlarmTimeText: View {
    let hour: Int
    let minute: Int
    var typography: AlarmTimeTypography
    var color: Color = .primary

    var body: some View {
        let parts = AlarmTimeFormat.parts(hour: hour, minute: minute)
        HStack(alignment: .firstTextBaseline, spacing: typography.spacing) {
            if parts.periodFirst, let period = parts.period {
                Text(period)
                    .font(typography.period)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            Text(parts.time)
                .font(typography.digits)
                .lineLimit(1)
                .minimumScaleFactor(typography.minimumScaleFactor)
            if !parts.periodFirst, let period = parts.period {
                Text(period)
                    .font(typography.period)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .layoutPriority(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(AlarmTimeFormat.display(hour: hour, minute: minute)))
    }
}

/// 一覧の時刻に使うフォントの組（#283）。
struct AlarmTimeTypography {
    let digits: Font
    let period: Font
    let spacing: CGFloat
    /// 数字をどこまで縮めてよいか（最大の文字サイズでは AM／PM を残すため広めに縮める）
    var minimumScaleFactor: CGFloat = 0.7

    /// 一覧の時刻。純正の時計に近い大きさ・細さにする（#283）。
    static func alarmList(isAccessibilitySize: Bool) -> AlarmTimeTypography {
        if isAccessibilitySize {
            return AlarmTimeTypography(
                digits: .system(.largeTitle).weight(.light),
                period: .system(.caption).weight(.regular),
                spacing: 4,
                minimumScaleFactor: 0.5
            )
        }
        return AlarmTimeTypography(
            digits: .system(size: 60, weight: .light),
            period: .system(size: 24, weight: .regular),
            spacing: 3
        )
    }
}
