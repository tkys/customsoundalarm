import Foundation
import StoreKit

/// 最初にインストールしたビルド番号（#124）。
/// `AppTransaction.originalAppVersion` は CFBundleVersion を返す。
enum FirstInstallBuild {
    static func load() async -> Int? {
        do {
            let result = try await AppTransaction.shared
            guard case .verified(let transaction) = result else { return nil }
            return AnalyticsUserProperties.firstInstallBuild(
                fromOriginalAppVersion: transaction.originalAppVersion
            )
        } catch {
            return nil
        }
    }
}
