import Foundation

/// サウンド選択画面の表示ロジック（純粋関数・単体テスト対象）。
enum SoundPickerLogic {

    /// プリセットセクションの既定開閉状態を判定する。
    /// - 自分の音が0件 → 開く（受け皿として見せる）
    /// - 自分の音が1件以上 → 畳む（場所を譲る）
    /// - Parameter importedCount: 自分の音（非プリセット）の件数
    /// - Parameter userOverride: ユーザーが手動で開閉したことがある場合はその値。nil = 未操作。
    static func presetExpandedDefault(importedCount: Int, userOverride: Bool? = nil) -> Bool {
        if let userOverride { return userOverride }
        return importedCount == 0
    }

    /// 「最近使った」セクションを表示するかを判定する。
    /// 音が少ないときは「自分の音」と重複して冗長になるため非表示にする。
    /// - Parameters:
    ///   - recentCount: 最近使った音の件数
    ///   - importedCount: 自分の音の件数
    ///   - threshold: この件数以上の自分の音があるときのみ最近使ったを表示（既定3）
    static func shouldShowRecent(recentCount: Int, importedCount: Int, threshold: Int = 3) -> Bool {
        guard recentCount > 0 else { return false }
        return importedCount >= threshold
    }
}
