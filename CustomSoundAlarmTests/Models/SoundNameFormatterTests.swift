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
    func screenshotTimestamp_fallsBackToDefault() {
        // スクリーンショットのタイムスタンプ名は識別にならない → 既定名
        #expect(
            SoundNameFormatter.sanitizedFileName("Screenshot_2026-01-15-104530.png", fallback: fallback)
            == fallback
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