import Foundation

/// `.loud.caf` の生成方式の版（#134）。
/// 古い版（またはメタデータ無し）は次の同期で作り直す。
struct LoudVariantMetadata: Codable, Equatable, Sendable {
    let version: Int

    static func shouldRegenerate(_ metadata: LoudVariantMetadata?) -> Bool {
        metadata?.version != LoudVariantGenerator.version
    }
}
