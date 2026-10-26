import Foundation

/// サウンド選択の計測用の種類（#124）
enum SoundSelectionKind: String, Sendable, Equatable {
    case imported
    case preset
    case `default`
}

/// サウンド選択の並び順バケット（#124）
enum SoundSelectionAnalytics {
    static func rankBucket(position: Int) -> String {
        switch position {
        case ..<1: return "1"
        case 1: return "1"
        case 2...3: return "2-3"
        case 4...10: return "4-10"
        default: return "11+"
        }
    }
}
