import SwiftUI

/// 端末の外観（ライト／ダーク）。PostHog の super property `ui_appearance` に使う（#291）。
/// 個人を特定しない値なので、ユーザープロパティではなく全イベント共通の値として送る。
enum AnalyticsAppearance: String, Sendable, CaseIterable {
    case light
    case dark

    init(colorScheme: ColorScheme) {
        self = colorScheme == .dark ? .dark : .light
    }

    /// super property のペイロード。
    var superProperties: [String: Any] {
        ["ui_appearance": rawValue]
    }
}
