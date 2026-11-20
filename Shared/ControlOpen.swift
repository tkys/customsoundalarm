import Foundation

/// コントロールセンターのボタンから開く先（#272）。
enum ControlOpenKind: String, Codable, Sendable, CaseIterable {
    /// アラーム一覧
    case list
    /// アラームを追加
    case add
}

/// コントロールから起動したときの実際の着地先。
enum ControlOpenDestination: Equatable, Sendable {
    case list
    case add
    /// オンボーディング中は通常どおりオンボーディングを出す
    case onboarding
}

/// コントロールの URL と着地先の判定（純ロジック・#272）。
enum ControlOpenLogic {
    static let scheme = "customsoundalarm"

    static func url(for kind: ControlOpenKind) -> URL {
        URL(string: "\(scheme)://control/\(kind.rawValue)")!
    }

    static func kind(from url: URL) -> ControlOpenKind? {
        guard url.scheme == scheme, url.host == "control" else { return nil }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return ControlOpenKind(rawValue: path)
    }

    static func destination(
        kind: ControlOpenKind,
        isOnboardingVisible: Bool
    ) -> ControlOpenDestination {
        if isOnboardingVisible { return .onboarding }
        switch kind {
        case .list: return .list
        case .add: return .add
        }
    }
}
