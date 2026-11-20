import Foundation
import AppIntents
import Observation

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

/// コントロールの着地先の判定（純ロジック・#272）。
enum ControlOpenLogic {
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

/// App Intent の perform からアプリの UI へ要求を渡す受け口（#272）。
/// Intent はアプリのプロセスで動くため、この共有インスタンスを RootTabView が監視する。
@MainActor
@Observable
final class ControlOpenRouter {
    static let shared = ControlOpenRouter()

    var pending: ControlOpenKind?

    private init() {}
}

/// コントロールセンターからアラーム一覧を開く（#272）。
struct OpenAlarmListFromControlIntent: AppIntent {
    static let title: LocalizedStringResource = "control_open_list"
    static let supportedModes: IntentModes = .foreground

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            ControlOpenRouter.shared.pending = .list
        }
        return .result()
    }
}

/// コントロールセンターからアラーム追加画面を開く（#272）。
struct AddAlarmFromControlIntent: AppIntent {
    static let title: LocalizedStringResource = "add_alarm"
    static let supportedModes: IntentModes = .foreground

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            ControlOpenRouter.shared.pending = .add
        }
        return .result()
    }
}
