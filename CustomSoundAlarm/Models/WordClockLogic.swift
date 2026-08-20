import Foundation

/// ワードクロック（#72 Phase1）の純粋ロジック（単体テスト対象）。
/// 「よる 10じ 20ふん」のように、該当語だけ点灯・非該当語は薄く残す表現。
/// 5分刻み（:00 は「ちょうど」）で時刻を語に割り当てる。
enum WordClockLogic {

    /// 分(0-59) を 5分刻みに切り捨てる（:23 → 20）
    static func roundedMinute(_ minute: Int) -> Int {
        (minute / 5) * 5
    }

    /// 切り捨て後の分 → 分語の index（0=ちょうど, 1=五分, ..., 11=五十五分）
    static func minuteIndex(minute: Int) -> Int {
        roundedMinute(minute) / 5
    }

    /// 時(0-23) → 時語の index（0=一時, ..., 11=十二時）。0時と12時は十二時
    static func hourIndex(hour: Int) -> Int {
        ((hour % 12) + 11) % 12
    }
}