import Foundation

/// アラーム一覧の許可バナーの条件（#230）。
enum PermissionBannerAction: Equatable, Sendable {
    /// 設定アプリを開く（拒否済み）。
    case openSettings
    /// システムの許可ダイアログを出す（未確認）。
    case requestAuthorization
}

enum PermissionBannerLogic {
    /// オンのアラームがあり、許可が拒否済みか未確認のときだけ出す。
    static func shouldShow(
        status: AlarmPermissionStatus,
        enabledAlarmCount: Int
    ) -> Bool {
        enabledAlarmCount > 0 && action(for: status) != nil
    }

    /// 状態に応じたボタンの動き。許可済みなどでは nil。
    static func action(for status: AlarmPermissionStatus) -> PermissionBannerAction? {
        switch status {
        case .denied: .openSettings
        case .notDetermined: .requestAuthorization
        case .authorized, .requestFailed, .unknown: nil
        }
    }
}
