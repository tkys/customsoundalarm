import Foundation

/// スヌーズ時間（分）を AlarmKit に渡す TimeInterval（秒）に変換する。
///
/// - Parameters:
///   - minutes: ユーザーが選択したスヌーズ時間（分）
///   - useSeconds: true の場合、minutes を「秒」として解釈する（DEBUG テストモード）
/// - Returns: 秒単位の TimeInterval
///
/// 通常時（useSeconds = false）: `minutes * 60`
/// DEBUG 秒モード時（useSeconds = true）: `minutes * 1`（5分設定なら5秒で再鳴動）
///
/// この関数は純粋で副作用が無いため、`#if DEBUG` の外からも単体テスト可能。
func snoozeInterval(minutes: Int, useSeconds: Bool) -> TimeInterval {
    TimeInterval(minutes * (useSeconds ? 1 : 60))
}
