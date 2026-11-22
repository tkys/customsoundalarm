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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(AlarmTimeFormat.display(hour: hour, minute: minute)))
    }
}
