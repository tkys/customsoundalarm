import Foundation

/// 動画トリム範囲のクランプロジック。
/// ジェスチャ中に毎回適用される純粋関数として振る舞い、
/// 以下の不変条件を保証する:
///   - `0 <= start < end <= duration`
///   - `end - start <= maxRange`（既定 30秒）
///   - `duration <= 0` のときは空範囲 `(0, 0)` を返す
///
/// 30秒制限は「そこで止める」挙動:
/// ハンドルを動かして上限を超える場合、もう一方のハンドル側へは移動させず、
/// 上限ギリギリで止める（意図しない範囲移動を防ぐ）。
struct TrimRange: Equatable, Sendable {
    var start: Double
    var end: Double
    let duration: Double
    var maxRange: Double

    /// `duration` が 0 以下のときは空範囲を返す安全イニシャライザ
    init(start: Double, end: Double, duration: Double, maxRange: Double = 30) {
        let safeDuration = max(duration, 0)
        self.duration = safeDuration
        self.maxRange = max(maxRange, 0)
        self.start = min(max(0, start), safeDuration)
        self.end = min(max(0, end), safeDuration)
    }

    /// 動画長が有効（> 0）かどうか
    var isValid: Bool { duration > 0 }

    /// 現在の選択範囲幅
    var width: Double { max(0, end - start) }

    /// `duration <= maxRange` のとき、全範囲 `(0, duration)` を返す
    static func fullRange(duration: Double, maxRange: Double = 30) -> TrimRange {
        if duration <= maxRange {
            return TrimRange(start: 0, end: duration, duration: duration, maxRange: maxRange)
        }
        return TrimRange(start: 0, end: maxRange, duration: duration, maxRange: maxRange)
    }

    /// 開始位置を移動する（終了を超えない・30秒上限で止まる）
    /// - Parameter newStart: ドラッグの目標位置
    /// - Returns: クランプされた新しい TrimRange
    func movingStart(to newStart: Double) -> TrimRange {
        guard isValid else { return self }
        // [0, end] の範囲に制限
        var clamped = min(max(0, newStart), end)
        // 30秒上限: start が end - maxRange より小さくなる場合は止める
        if end - clamped > maxRange {
            clamped = max(0, end - maxRange)
        }
        return TrimRange(start: clamped, end: end, duration: duration, maxRange: maxRange)
    }

    /// 終了位置を移動する（開始より後・30秒上限で止まる）
    /// - Parameter newEnd: ドラッグの目標位置
    /// - Returns: クランプされた新しい TrimRange
    func movingEnd(to newEnd: Double) -> TrimRange {
        guard isValid else { return self }
        // [start, duration] の範囲に制限
        var clamped = min(max(start, newEnd), duration)
        // 30秒上限: end が start + maxRange より大きくなる場合は止める
        if clamped - start > maxRange {
            clamped = min(duration, start + maxRange)
        }
        return TrimRange(start: start, end: clamped, duration: duration, maxRange: maxRange)
    }

    /// 選択範囲全体を平行移動する（幅を保つ）。
    /// 写真アプリのトリマーと同様、選択範囲の内側をドラッグしたときに呼ばれる。
    ///
    /// - Parameter delta: 移動量（秒）。正=右方向、負=左方向。
    /// - Returns: 幅を保ったまま `[0, duration]` にクランプされた新しい TrimRange。
    ///   範囲の幅が `duration` より大きい（異常状態）場合は移動しない。
    func movingRange(by delta: Double) -> TrimRange {
        guard isValid else { return self }
        let w = width
        guard w <= duration else { return self }
        // 移動後の start/end を計算 → [0, duration] にクランプ
        var newStart = start + delta
        var newEnd = end + delta
        if newStart < 0 {
            newStart = 0
            newEnd = w
        }
        if newEnd > duration {
            newEnd = duration
            newStart = duration - w
        }
        return TrimRange(start: newStart, end: newEnd, duration: duration, maxRange: maxRange)
    }
}
