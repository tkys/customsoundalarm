import SwiftUI

/// 一覧の時刻の大きさの比較（DEBUGのみ・#283）。
///
/// 実機で現在の見た目と純正の時計に近い案を見比べるための切り替え。
/// 決まった案だけを残すまでの一時的なもの。
enum AlarmTimeSizeOption: String, CaseIterable, Identifiable {
    /// 今の見た目（44pt・丸い字体・標準の太さ）
    case current
    /// 純正寄り（56pt・細め）
    case clock56
    /// 純正寄り（60pt・細め）
    case clock60

    static let debugDefaultsKey = "debug.alarmTimeSize"
    static let launchArgumentPrefix = "-uitest-alarm-time-size="

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .current: "現在（44pt・丸）"
        case .clock56: "純正寄り（56pt・細）"
        case .clock60: "純正寄り（60pt・細）"
        }
    }

    /// UIテスト・録画用の起動引数。指定がなければ nil。
    static var launchSelection: AlarmTimeSizeOption? {
        #if DEBUG
        guard let argument = CommandLine.arguments.first(where: {
            $0.hasPrefix(launchArgumentPrefix)
        }) else { return nil }
        return AlarmTimeSizeOption(
            rawValue: String(argument.dropFirst(launchArgumentPrefix.count))
        )
        #else
        return nil
        #endif
    }

    /// 時刻の数字と AM／PM のフォント。
    func typography(isAccessibilitySize: Bool) -> AlarmTimeTypography {
        switch self {
        case .current:
            if isAccessibilitySize {
                return AlarmTimeTypography(
                    digits: .system(.largeTitle, design: .rounded).weight(.regular),
                    period: .system(.caption, design: .rounded).weight(.medium),
                    spacing: 4,
                    minimumScaleFactor: 0.5
                )
            }
            return AlarmTimeTypography(
                digits: .system(size: 44, weight: .regular, design: .rounded),
                period: .system(size: 19, weight: .medium, design: .rounded),
                spacing: 2
            )
        case .clock56:
            if isAccessibilitySize {
                return AlarmTimeTypography(
                    digits: .system(.largeTitle).weight(.light),
                    period: .system(.caption).weight(.regular),
                    spacing: 4,
                    minimumScaleFactor: 0.5
                )
            }
            return AlarmTimeTypography(
                digits: .system(size: 56, weight: .light),
                period: .system(size: 22, weight: .regular),
                spacing: 3
            )
        case .clock60:
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
}

/// 一覧の時刻に使うフォントの組（#283）。
struct AlarmTimeTypography {
    let digits: Font
    let period: Font
    let spacing: CGFloat
    /// 数字をどこまで縮めてよいか（最大の文字サイズでは AM／PM を残すため広めに縮める）
    var minimumScaleFactor: CGFloat = 0.7
}
