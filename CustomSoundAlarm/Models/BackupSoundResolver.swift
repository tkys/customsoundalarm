import Foundation

/// 最終アラーム（寝過ごし防止）で使う音の決め方（#119）。
/// 大きくした版があればそれ、無い/生成失敗/標準音なら予備音。
enum BackupSoundResolver {

    static func variantFileName(for sourceFileName: String) -> String? {
        guard !sourceFileName.isEmpty else { return nil }
        return LoudVariantGenerator.outputFileName(for: sourceFileName)
    }

    /// - Parameters:
    ///   - sourceFileName: アラームに設定された音（空 = 標準音）
    ///   - availableVariantFileName: 実際に存在する大きくした版のファイル名
    ///   - fallbackFileName: 予備音
    static func resolve(
        sourceFileName: String,
        availableVariantFileName: String?,
        fallbackFileName: String
    ) -> String {
        guard !sourceFileName.isEmpty, let availableVariantFileName else {
            return fallbackFileName
        }
        return availableVariantFileName
    }
}
