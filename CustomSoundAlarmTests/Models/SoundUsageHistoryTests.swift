import Testing
import Foundation
@testable import CustomSoundAlarm

/// `SoundUsageHistory` の「新しい順ソート／未使用除外／削除済み音除外／上限切り詰め／記録と読出」
/// を検証する。純粋関数は直接、UserDefaults 依存部は `clear()` で孤立化させる。
/// すべて共有 UserDefaults を触るため直列実行する。
@Suite(.serialized)
struct SoundUsageHistoryTests {

    /// UserDefaults を使うテストの前処理: 履歴と #6 レガシーキーを完全クリア。
    private func resetHistory() {
        SoundUsageHistory.clear()
    }

    // MARK: - 純粋関数: sortedNewestFirst（新しい順ソート）

    @Test
    func sortedNewestFirst_ordersByDateDescending() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let map: [String: TimeInterval] = [
            "old.caf": base.addingTimeInterval(-3600).timeIntervalSince1970,
            "newest.caf": base.addingTimeInterval(0).timeIntervalSince1970,
            "mid.caf": base.addingTimeInterval(-1800).timeIntervalSince1970
        ]

        let sorted = SoundUsageHistory.sortedNewestFirst(map).map(\.fileName)

        #expect(sorted == ["newest.caf", "mid.caf", "old.caf"])
    }

    @Test
    func sortedNewestFirst_emptyMapReturnsEmpty() {
        #expect(SoundUsageHistory.sortedNewestFirst([:]).isEmpty)
    }

    // MARK: - 純粋関数: pruneToLimit（上限切り詰め）

    @Test
    func pruneToLimit_keepsNewest() {
        let t: TimeInterval = 1_000_000
        let map: [String: TimeInterval] = [
            "a.caf": t, "b.caf": t + 1, "c.caf": t + 2, "d.caf": t + 3
        ]

        let pruned = SoundUsageHistory.pruneToLimit(map, limit: 2)

        #expect(pruned.count == 2)
        // 新しい順上位2件は d, c
        let kept = SoundUsageHistory.sortedNewestFirst(pruned).map(\.fileName)
        #expect(kept == ["d.caf", "c.caf"])
    }

    @Test
    func pruneToLimit_underLimitReturnsUnchanged() {
        let map: [String: TimeInterval] = ["a.caf": 1, "b.caf": 2]
        let pruned = SoundUsageHistory.pruneToLimit(map, limit: 5)
        #expect(pruned.count == 2)
    }

    @Test
    func pruneToLimit_zeroLimitReturnsEmpty() {
        let map: [String: TimeInterval] = ["a.caf": 1, "b.caf": 2]
        #expect(SoundUsageHistory.pruneToLimit(map, limit: 0).isEmpty)
    }

    // MARK: - recentFileNames（未使用除外・削除済み除外・上限）

    @Test
    func recentFileNames_excludesDeletedFiles() {
        resetHistory()
        // 履歴に a, b, deleted.caf を記録
        SoundUsageHistory.recordUsage("a.caf", at: Date(timeIntervalSince1970: 1))
        SoundUsageHistory.recordUsage("b.caf", at: Date(timeIntervalSince1970: 2))
        SoundUsageHistory.recordUsage("deleted.caf", at: Date(timeIntervalSince1970: 3))

        // 現存する音は a, b のみ（deleted.caf は削除済みと想定）
        let existing: Set<String> = ["a.caf", "b.caf"]

        let recent = SoundUsageHistory.recentFileNames(limit: 5, existingFileNames: existing)

        // 削除済み deleted.caf は除外される（新しい順: b, a）
        #expect(recent == ["b.caf", "a.caf"])
        #expect(!recent.contains("deleted.caf"))
    }

    @Test
    func recentFileNames_returnsNewestFirst() {
        resetHistory()
        SoundUsageHistory.recordUsage("first.caf", at: Date(timeIntervalSince1970: 100))
        SoundUsageHistory.recordUsage("second.caf", at: Date(timeIntervalSince1970: 200))
        SoundUsageHistory.recordUsage("third.caf", at: Date(timeIntervalSince1970: 300))

        let existing: Set<String> = ["first.caf", "second.caf", "third.caf"]
        let recent = SoundUsageHistory.recentFileNames(limit: 10, existingFileNames: existing)

        // 新しい順
        #expect(recent == ["third.caf", "second.caf", "first.caf"])
    }

    @Test
    func recentFileNames_respectsLimit() {
        resetHistory()
        for i in 0..<7 {
            SoundUsageHistory.recordUsage("sound\(i).caf", at: Date(timeIntervalSince1970: TimeInterval(i)))
        }
        let existing = Set((0..<7).map { "sound\($0).caf" })

        let recent = SoundUsageHistory.recentFileNames(limit: 3, existingFileNames: existing)

        // 新しい順上位3件: sound6, sound5, sound4
        #expect(recent == ["sound6.caf", "sound5.caf", "sound4.caf"])
    }

    @Test
    func recentFileNames_unusedSoundsExcluded() {
        resetHistory()
        SoundUsageHistory.recordUsage("used.caf", at: Date(timeIntervalSince1970: 5))
        // unused.caf は履歴にない
        let existing: Set<String> = ["used.caf", "unused.caf"]

        let recent = SoundUsageHistory.recentFileNames(limit: 5, existingFileNames: existing)

        // 履歴にない unused.caf は出現しない
        #expect(recent == ["used.caf"])
        #expect(!recent.contains("unused.caf"))
    }

    @Test
    func recentFileNames_emptyWhenNoHistory() {
        resetHistory()
        let existing: Set<String> = ["a.caf"]
        #expect(SoundUsageHistory.recentFileNames(limit: 5, existingFileNames: existing).isEmpty)
    }

    // MARK: - recordUsage / lastUsedFileName 往復

    @Test
    func recordUsage_updatesLastUsedFileName() {
        resetHistory()
        #expect(SoundUsageHistory.lastUsedFileName == nil)

        SoundUsageHistory.recordUsage("a.caf", at: Date(timeIntervalSince1970: 100))
        #expect(SoundUsageHistory.lastUsedFileName == "a.caf")

        SoundUsageHistory.recordUsage("b.caf", at: Date(timeIntervalSince1970: 200))
        #expect(SoundUsageHistory.lastUsedFileName == "b.caf")

        // a.caf を再度使ったら a が最新に
        SoundUsageHistory.recordUsage("a.caf", at: Date(timeIntervalSince1970: 300))
        #expect(SoundUsageHistory.lastUsedFileName == "a.caf")
    }

    @Test
    func recordUsage_ignoresEmptyFileName() {
        resetHistory()
        SoundUsageHistory.recordUsage("", at: Date(timeIntervalSince1970: 100))
        #expect(SoundUsageHistory.lastUsedFileName == nil)
    }

    @Test
    func recordUsage_capsHistoryToMaxEntries() {
        resetHistory()
        // maxEntries(20) を超えて記録
        for i in 0..<30 {
            SoundUsageHistory.recordUsage("s\(i).caf", at: Date(timeIntervalSince1970: TimeInterval(i)))
        }
        let existing = Set((0..<30).map { "s\($0).caf" })

        // 新しい順に最近使ったものを取得。履歴マップは 20 件に切り詰められているはず。
        let recent = SoundUsageHistory.recentFileNames(limit: 30, existingFileNames: existing)
        #expect(recent.count == 20)
        // 最新(s29)が先頭、s10 まで残る（s0..s9 は prune で除去）
        #expect(recent.first == "s29.caf")
        #expect(recent.last == "s10.caf")
        #expect(!recent.contains("s0.caf"))
    }

    // MARK: - #6 レガシーマイグレーション

    @Test
    func migratesLegacySingleLastUsedSound() {
        resetHistory()
        // #6 形式: 単一値を直接 UserDefaults に書く
        AppGroup.userDefaults.set("legacy.caf", forKey: "last_used_sound_file_name")

        // lastUsedFileName 参照でマイグレーション発動
        let migrated = SoundUsageHistory.lastUsedFileName
        #expect(migrated == "legacy.caf")

        // レガシーキーは除去され、新マップキーに移行されている
        #expect(AppGroup.userDefaults.string(forKey: "last_used_sound_file_name") == nil)
        #expect(AppGroup.userDefaults.dictionary(forKey: "sound_usage_history") != nil)
    }
}
