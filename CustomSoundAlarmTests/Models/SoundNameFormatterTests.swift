import Testing
import Foundation
@testable import CustomSoundAlarm

/// 取り込み時の音源名整形（#93-2a）を検証する。
/// 既存ユーザーの保存済み名には適用しない（取り込み時のみ）。
struct SoundNameFormatterTests {

    private let fallback = "Imported sound"

    // MARK: - 基本整形

    @Test
    func plainName_unchanged() {
        #expect(SoundNameFormatter.sanitizedFileName("concert.mp4", fallback: fallback) == "concert")
        #expect(SoundNameFormatter.sanitizedFileName("TeamMeeting", fallback: fallback) == "TeamMeeting")
    }

    @Test
    func stripsExtension() {
        #expect(SoundNameFormatter.sanitizedFileName("vacation.mov", fallback: fallback) == "vacation")
        #expect(SoundNameFormatter.sanitizedFileName("sound.caf", fallback: fallback) == "sound")
    }

    @Test
    func japaneseName_unchanged() {
        #expect(SoundNameFormatter.sanitizedFileName("演奏録画.m4v", fallback: fallback) == "演奏録画")
    }

    // MARK: - 記号の置換

    @Test
    func underscoresAndHyphens_becomeSpaces() {
        #expect(SoundNameFormatter.sanitizedFileName("my_favorite-song.mp3", fallback: fallback) == "my favorite song")
    }

    @Test
    func collapsesConsecutiveSeparators() {
        #expect(SoundNameFormatter.sanitizedFileName("a__--b.mp3", fallback: fallback) == "a b")
        #expect(SoundNameFormatter.sanitizedFileName("  a   b .wav", fallback: fallback) == "a b")
    }

    @Test
    func trimsWhitespace() {
        #expect(SoundNameFormatter.sanitizedFileName("_Morning_Alarm_.mp3", fallback: fallback) == "Morning Alarm")
    }

    // MARK: - UUID 除去

    @Test
    func removesEmbeddedUUID() {
        let raw = "My Song 550E8400-E29B-41D4-A716-446655440000.mp4"
        #expect(SoundNameFormatter.sanitizedFileName(raw, fallback: fallback) == "My Song")
    }

    @Test
    func uuidOnlyName_fallsBackToDefault() {
        #expect(SoundNameFormatter.sanitizedFileName("550e8400-e29b-41d4-a716-446655440000.mov", fallback: fallback) == fallback)
    }

    // MARK: - ランダムスラグ連鎖の除去（#93 の実例）

    @Test
    func issueExample_randomSlug_fallsBackToDefault() {
        // Issue #93 の実例: ダウンロードした動画のファイル名
        let raw = "h_086xmom11_mhb_w-1F-BAA37D-52D9-44C1-A62B-D88FA49AD5BA.mp4"
        #expect(SoundNameFormatter.sanitizedFileName(raw, fallback: fallback) == fallback)
    }

    @Test
    func randomSlugAfterSpace_removesOnlySlug() {
        // 空白で区切られた前置きは残る（チェーンは空白をまたがない）
        let raw = "Best Song h_086xmom11_mhb_w-1F-BAA37D-52D9.mp4"
        #expect(SoundNameFormatter.sanitizedFileName(raw, fallback: fallback) == "Best Song")
    }

    @Test
    func prefixConnectedByUnderscore_fallsBackToDefault() {
        // _ でチェーンに繋がった前置きはチェーンの一部とみなされ全体が除去される。
        // （正当なタイトルが _ 繋ぎでスラグに連結されるケースは稀で、
        //   名前は取り込み後に編集できるため許容するトレードオフ）
        let raw = "Best_Song_h_086xmom11_mhb_w-1F-BAA37D-52D9.mp4"
        #expect(SoundNameFormatter.sanitizedFileName(raw, fallback: fallback) == fallback)
    }

    @Test
    func albumTrackNumbering_isKept() {
        // 01_Track_Title のような命名: 数字入りグループが1個だけ → 残す
        #expect(
            SoundNameFormatter.sanitizedFileName("01_Favorite_Song_Morning.mp3", fallback: fallback)
            == "01 Favorite Song Morning"
        )
    }

    @Test
    func underscoredTitleWithoutDigits_isKept() {
        // 数字を含まない正当なタイトル → 残す（記号だけ空白化）
        #expect(
            SoundNameFormatter.sanitizedFileName("Eine_Kleine_Nachtmusik.mp3", fallback: fallback)
            == "Eine Kleine Nachtmusik"
        )
    }

    @Test
    func screenshotTimestamp_isKept() {
        // タイムスタンプ名は混在グループを持たないため残る（#93 レビューの安全側倒し:
        // 誤判定の害が非対称で、汚い名前は編集できるが消えた曲名は復旧不能）
        #expect(
            SoundNameFormatter.sanitizedFileName("Screenshot_2026-01-15-104530.png", fallback: fallback)
            == "Screenshot 2026 01 15 104530"
        )
    }

    // MARK: - レビュー検証表の8件（#93 レビュー・そのままテストケース化）

    /// 新判定「英字と数字が混在し6文字以上のグループが2個以上」の検証セット。
    /// クラシックの作品番号形式（No9 / Op125 / K525 / Op32 / No4 / Op67）は
    /// 短く意味のある接頭辞を持つため除去されない（再発しやすいので必須ケース）
    @Test
    func reviewTable_removes() {
        // 除去したいもの（英数混在6文字以上 × 2 を含む）
        #expect(SoundNameFormatter.sanitizedFileName("h_086xmom11_mhb_w-1F-BAA37D.mp4", fallback: fallback) == fallback)
        #expect(SoundNameFormatter.sanitizedFileName("yt5s_io_A1b2C3d4E5_f6G7h8I9j0.mp4", fallback: fallback) == fallback)
    }

    @Test
    func reviewTable_classicalWorkNumbers_areKept() {
        // クラシックの作品番号（実機テスト素材がモーツァルトとホルストだったため実害あり得た領域）
        #expect(
            SoundNameFormatter.sanitizedFileName("Beethoven_Symphony_No9_Op125.mp3", fallback: fallback)
            == "Beethoven Symphony No9 Op125"
        )
        #expect(
            SoundNameFormatter.sanitizedFileName("Mozart_K525_Movement_1.mp3", fallback: fallback)
            == "Mozart K525 Movement 1"
        )
        #expect(
            SoundNameFormatter.sanitizedFileName("Symphony_No5_in_C_minor_Op67.mp3", fallback: fallback)
            == "Symphony No5 in C minor Op67"
        )
        #expect(
            SoundNameFormatter.sanitizedFileName("The_Planets_Op32_No4_Jupiter.mp3", fallback: fallback)
            == "The Planets Op32 No4 Jupiter"
        )
    }

    @Test
    func reviewTable_miscLegitimateNames_areKept() {
        #expect(
            SoundNameFormatter.sanitizedFileName("Bohemian_Rhapsody_1975_Remaster.mp3", fallback: fallback)
            == "Bohemian Rhapsody 1975 Remaster"
        )
        // 混在グループが1個だけ（Final1234567890）→ 除去しない（安全側の外れは許容）
        #expect(
            SoundNameFormatter.sanitizedFileName("RPReplay_Final1234567890.mp4", fallback: fallback)
            == "RPReplay Final1234567890"
        )
    }

    @Test
    func photoLibraryName_isKeptWithSpace() {
        // IMG_1234: 英数合計 8 文字 → スラグ判定されず空白化のみ
        #expect(SoundNameFormatter.sanitizedFileName("IMG_1234.MOV", fallback: fallback) == "IMG 1234")
    }

    @Test
    func shortHyphenatedName_isKept() {
        // 短いハイフン名はスラグ判定しない
        #expect(SoundNameFormatter.sanitizedFileName("BAA37D-52D9.mp3", fallback: fallback) == "BAA37D 52D9")
    }

    // MARK: - 空になった場合の既定名

    @Test
    func separatorOnlyName_fallsBackToDefault() {
        #expect(SoundNameFormatter.sanitizedFileName("___---_.mp3", fallback: fallback) == fallback)
        #expect(SoundNameFormatter.sanitizedFileName("", fallback: fallback) == fallback)
    }

    @Test
    func defaultName_isLocalized() {
        // 既定名のローカライズ（テスト環境では en リソースが載る）
        #expect(!SoundNameFormatter.defaultName.isEmpty)
    }
}