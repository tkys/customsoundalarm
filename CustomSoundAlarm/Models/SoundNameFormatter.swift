import Foundation

/// 取り込み時の音源名整形（#93-2a・純粋関数）。
///
/// ダウンロードした動画や画面録画のファイル名（`h_086xmom11_mhb_w-1F-...` のような
/// UUID・ランダム文字列を含む名前）をそのまま音源名にすると一覧が識別不能になるため、
/// 取り込み時に次の整形を施す:
///
/// 1. 拡張子を除去
/// 2. UUID（8-4-4-4-12 形式の16進）を除去
/// 3. ランダムなスラグ連鎖を除去: `-` / `_` で結合された英数グループの連鎖のうち、
///    英数合計が 16 文字以上かつ**数字を含むグループが 2 個以上**のもの
///    （`h_086xmom11_mhb_w-1F-BAA37D-...` のような名前。アルバムの `01_Track_Title` のように
///    数字が先頭グループだけ、または `Eine_Kleine_Nachtmusik` のように数字を含まない
///    正当なタイトルは残す）
/// 4. 残った `-` / `_` を空白に置換し、連続空白を 1 つにまとめる
/// 5. 結果が空になったら既定名（"Imported sound"）を返す
///
/// ⚠️ **取り込み時のみ適用する。** 既に保存された名前（ユーザーが自分で付けた名前を
/// 含む）に後から適用すると名前を壊す（#93 の制約）。
enum SoundNameFormatter {

    /// 整形の結果空だった場合の既定名
    static var defaultName: String {
        String(localized: "imported_sound_default")
    }

    /// ファイル名（拡張子付き可）を整形して音源名を返す。
    /// - Parameters:
    ///   - rawFileName: 取り込み元のファイル名（`url.lastPathComponent` 相当）
    ///   - fallback: 整形結果が空だった場合の名前（既定は ローカライズ済みの "Imported sound"）。
    ///     テストで決定的にするために注入可能
    static func sanitizedFileName(_ rawFileName: String, fallback: String? = nil) -> String {
        // 1. 拡張子除去
        var name = (rawFileName as NSString).deletingPathExtension

        // 2. UUID 除去（8-4-4-4-12 形式の16進）
        name = name.replacingOccurrences(
            of: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}",
            with: " ",
            options: .regularExpression
        )

        // 3. ランダムなスラグ連鎖の除去
        name = removeRandomSlugChains(name)

        // 4. 記号を空白に置換
        name = name.replacingOccurrences(of: "_", with: " ")
        name = name.replacingOccurrences(of: "-", with: " ")

        // 5. 連続空白を1つにまとめて前後を除去
        let collapsed = name
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        if collapsed.isEmpty {
            return fallback ?? defaultName
        }
        return collapsed
    }

    /// `-` / `_` で結合された英数グループの連鎖のうち、ランダム文字列と判断できるものを除去する。
    /// 判定: 英数合計 >= 16 文字 かつ 数字を含むグループが 2 個以上。
    private static func removeRandomSlugChains(_ name: String) -> String {
        let pattern = "[A-Za-z0-9]+(?:[-_][A-Za-z0-9]+)+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return name }

        var result = name
        let matches = regex.matches(
            in: name,
            range: NSRange(name.startIndex..., in: name)
        )
        // 後ろから置換して range のずれを防ぐ
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result),
                  isRandomSlugChain(String(result[range])) else { continue }
            result.replaceSubrange(range, with: " ")
        }
        return result
    }

    /// スラグ連鎖がランダム文字列か（英数合計 >= 16 かつ数字入りグループ >= 2）
    private static func isRandomSlugChain(_ slug: String) -> Bool {
        let groups = slug.split(whereSeparator: { $0 == "-" || $0 == "_" })
        guard !groups.isEmpty else { return false }

        let alnumCount = groups.reduce(0) { $0 + $1.count }
        let digitGroups = groups.filter { $0.contains(where: \.isNumber) }.count
        return alnumCount >= 16 && digitGroups >= 2
    }
}