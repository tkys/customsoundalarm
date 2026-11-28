import Foundation

/// 取り込んだ音の種類（#202）。画面には出さず、保存と計測だけに使う。
enum SoundContentKind: String, Codable, Sendable, CaseIterable, Hashable {
    case singing
    case instrumental
    case voice
    case cat
    case dog
    case bird
    case nature
    case other
    case unknown
}
