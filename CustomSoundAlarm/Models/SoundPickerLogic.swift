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

    /// 「追加した音」を最近使った順に並べる（#123）。
    /// 履歴に無い音は元の順序のまま後ろに置く。
    static func mySoundsByRecentUse(
        in sounds: [AlarmSound],
        recentFileNames: [String]
    ) -> [AlarmSound] {
        let imported = sounds.filter { !$0.isPreset }
        // 同じ名前が2回あっても落ちないよう、先に出た（新しい）方を採る
        let rank = Dictionary(
            recentFileNames.enumerated().map { ($0.element, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        return imported.enumerated()
            .sorted { lhs, rhs in
                let left = rank[lhs.element.fileName] ?? Int.max
                let right = rank[rhs.element.fileName] ?? Int.max
                if left != right { return left < right }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// My Sounds セクションに表示する音源（#85）。
    ///
    /// **所有する非プリセット音源の完全な一覧**を返す。使用済み（Recent に載っている）か
    /// どうかで除外しない。かつては Recent との重複を避けて除外していたが、
    /// 「一度使った音源が消える」「保有1〜2本で Recent が非表示のとき完全に不可視になる」
    /// 問題があった。Recent は「よく使うものへの近道」であり、両方に同じ音が出るのは
    /// 自然（写真アプリの「最近の項目」とアルバムの関係と同じ）。
    static func mySounds(in sounds: [AlarmSound]) -> [AlarmSound] {
        sounds.filter { !$0.isPreset }
    }

    /// Preset セクションに表示する音源（#85 レビュー）。
    ///
    /// **プリセット音源の完全な一覧**を返す。mySounds と同じ規則（所有する音源の
    /// 完全な一覧・Recent による除外をしない）に従う。プリセット利用者は
    /// インポート音源0本のことが多く、その場合 Recent は常に非表示
    /// （「最近使った」を統合したため）のため、
    /// 除外すると使ったプリセットがどこにも出なくなる。
    static func presetSounds(in sounds: [AlarmSound]) -> [AlarmSound] {
        sounds.filter { $0.isPreset }
    }
}

/// 音を選ぶ画面で行をタップしたときの試し聴き（#196・純粋関数・単体テスト対象）。
///
/// 標準の時計アプリと同じく、タップで選ぶと同時に鳴らす。
/// 同じ行をもう一度タップしたら止める（選択は変えない）。
enum SoundPreviewLogic {

    /// 行をタップしたときの動き。
    enum Tap: Equatable {
        /// 選んで鳴らす（別の行から切り替える場合も含む）
        case selectAndPlay
        /// 鳴っている同じ行をもう一度タップ → 止める（選択はそのまま）
        case stop
        /// 鳴らせない行（既定の音）を選ぶ。鳴っている音は止める
        case selectOnly
    }

    /// 行をタップしたときの動きを返す。
    /// - Parameters:
    ///   - tapped: タップした行の音（既定の音の行は nil）
    ///   - playingFileName: いま鳴っているファイル名
    static func tap(tapped: AlarmSound?, playingFileName: String?) -> Tap {
        guard let tapped else { return .selectOnly }
        return playingFileName == tapped.fileName ? .stop : .selectAndPlay
    }

    /// 選択が実際に変わったか。同じ行の再タップ（停止）で
    /// `sound_selected` を二重に送らないために使う。
    static func selectionChanged(tapped: AlarmSound?, selected: AlarmSound?) -> Bool {
        switch (tapped, selected) {
        case (nil, nil):
            return false
        case (nil, _), (_, nil):
            return true
        case let (tapped?, selected?):
            return tapped.id != selected.id
        }
    }

    /// 試し聴きを止める必要があるか（鳴っているときだけ）。
    /// 画面を閉じる・保存する・取り込みを始める、のどの導線でも使う（#196）。
    static func shouldStop(playingFileName: String?) -> Bool {
        playingFileName != nil
    }
}
