import Foundation

/// プリセット音源の登録判定を行う純粋関数。
///
/// 罠1: ユーザーが削除したプリセットは `dismissedPresetFileNames` に記録され、
/// 再起動時の再登録対象から除外される。アプリ更新で新規プリセットが追加された
/// 場合は、未登録かつ未削除なので登録される。
enum PresetRegistration {

    /// プリセット定義（fileName とローカライズキー）
    struct Definition: Equatable, Sendable {
        let fileName: String
        let labelKey: String
    }

    /// 登録すべきプリセット定義を返す。
    /// - Parameters:
    ///   - definitions: 全プリセット定義（`SoundStore.presetDefinitions`）
    ///   - existingFileNames: 既に `sounds` に存在する fileName の集合
    ///   - dismissedFileNames: ユーザーが削除した fileName の集合
    /// - Returns: 未登録かつ未削除のプリセット定義（登録対象）
    static func presetsToRegister(
        definitions: [Definition],
        existingFileNames: Set<String>,
        dismissedFileNames: Set<String>
    ) -> [Definition] {
        definitions.filter { def in
            !existingFileNames.contains(def.fileName)
            && !dismissedFileNames.contains(def.fileName)
        }
    }
}
