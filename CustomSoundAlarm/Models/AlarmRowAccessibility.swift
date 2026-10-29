import Foundation

/// アラーム一覧の行の VoiceOver 読み上げ（#123）。
enum AlarmRowAccessibility {
    /// オン/オフスイッチの読み上げ名。「〈時刻〉 〈ラベル〉」。
    /// ラベルが空なら時刻だけ。
    static func toggleLabel(time: String, label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? time : "\(time) \(trimmed)"
    }
}
