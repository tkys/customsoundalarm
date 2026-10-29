import Foundation

/// 計測のユーザープロパティ用の純ロジック（#124）。
enum AnalyticsUserProperties {

    /// 寝過ごし防止がオンのアラーム数
    static func backupAlarmCount(alarms: [AlarmEntry]) -> Int {
        alarms.filter { $0.backupMinutes != nil }.count
    }

    /// `AppTransaction.originalAppVersion`（CFBundleVersion）を Int にする。
    /// 取れない・数値でない場合は nil（送らない）。
    static func firstInstallBuild(fromOriginalAppVersion version: String?) -> Int? {
        guard let version else { return nil }
        let trimmed = version.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let build = Int(trimmed), build >= 0 else {
            return nil
        }
        return build
    }
}
