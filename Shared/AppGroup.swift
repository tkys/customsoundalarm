import Foundation

/// App Group共有コンテナへのアクセス
/// すべてのアラームを休む区間（#197 画面作り直し）。
///
/// 押したときにオンだったアラームの ID だけを持つ。あとから作った／
/// オンにし直したアラームは入らないので、休み中でも鳴る。
struct GlobalSkip: Codable, Equatable, Sendable {
    var start: Date
    var end: Date
    var entryIDs: [UUID]
    /// 1.8.4 までに全体の休みで止めた1回きりのアラーム（取り消すときに戻す）。
    /// 1.8.5 からはトグルを変えずに休むため、新しくは増えない（#305）。
    var disabledOneTimeIDs: [UUID]

    init(
        start: Date,
        end: Date,
        entryIDs: [UUID],
        disabledOneTimeIDs: [UUID] = []
    ) {
        self.start = start
        self.end = end
        self.entryIDs = entryIDs
        self.disabledOneTimeIDs = disabledOneTimeIDs
    }

    var isActive: Bool {
        end > Date() && !entryIDs.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case start, end, entryIDs, disabledOneTimeIDs
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decode(Date.self, forKey: .start)
        end = try container.decode(Date.self, forKey: .end)
        entryIDs = try container.decodeIfPresent([UUID].self, forKey: .entryIDs) ?? []
        disabledOneTimeIDs = try container.decodeIfPresent(
            [UUID].self,
            forKey: .disabledOneTimeIDs
        ) ?? []
    }
}

enum AppGroup {
    static let identifier = "group.com.tkysdev.customsoundalarm"

    static var containerURL: URL {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        )!
    }

    static var userDefaults: UserDefaults {
        UserDefaults(suiteName: identifier)!
    }

    /// 初回インストールバージョン（起動時に1度だけ記録）
    static var firstInstallVersion: String? {
        get { userDefaults.string(forKey: "first_install_version") }
        set { userDefaults.set(newValue, forKey: "first_install_version") }
    }

    /// 初回起動日（広告の7日間猶予・#111）
    static var firstLaunchDate: Date? {
        get { userDefaults.object(forKey: "first_launch_date") as? Date }
        set { userDefaults.set(newValue, forKey: "first_launch_date") }
    }

    /// 最後に全画面広告を出した日時（週1回の制御・#111）
    static var lastInterstitialShownAt: Date? {
        get { userDefaults.object(forKey: "last_interstitial_shown_at") as? Date }
        set {
            if let newValue {
                userDefaults.set(newValue, forKey: "last_interstitial_shown_at")
            } else {
                userDefaults.removeObject(forKey: "last_interstitial_shown_at")
            }
        }
    }

    /// アップデート設定のキャッシュ（#116）
    static var cachedAppConfigData: Data? {
        get { userDefaults.data(forKey: "cached_app_config_data") }
        set {
            if let newValue {
                userDefaults.set(newValue, forKey: "cached_app_config_data")
            } else {
                userDefaults.removeObject(forKey: "cached_app_config_data")
            }
        }
    }

    /// アップデート設定を最後に取得した日時（キャッシュの鮮度判定・#116）
    static var cachedAppConfigFetchedAt: Date? {
        get { userDefaults.object(forKey: "cached_app_config_fetched_at") as? Date }
        set {
            if let newValue {
                userDefaults.set(newValue, forKey: "cached_app_config_fetched_at")
            } else {
                userDefaults.removeObject(forKey: "cached_app_config_fetched_at")
            }
        }
    }

    /// アップデート設定を最後に確認した日時（1時間に1回の制限・#116）
    static var lastUpdateCheckAt: Date? {
        get { userDefaults.object(forKey: "last_update_check_at") as? Date }
        set {
            if let newValue {
                userDefaults.set(newValue, forKey: "last_update_check_at")
            } else {
                userDefaults.removeObject(forKey: "last_update_check_at")
            }
        }
    }

    /// 「あとで」で閉じたおすすめの latest_build（#116）
    static var dismissedRecommendedBuild: Int? {
        get {
            guard userDefaults.object(forKey: "dismissed_recommended_build") != nil else { return nil }
            return userDefaults.integer(forKey: "dismissed_recommended_build")
        }
        set {
            if let newValue {
                userDefaults.set(newValue, forKey: "dismissed_recommended_build")
            } else {
                userDefaults.removeObject(forKey: "dismissed_recommended_build")
            }
        }
    }

    /// UIテスト用: 必須アップデートを強制（DEBUGのみ・#116）
    static var isUITestUpdateRequired: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-update-required")
    #else
        false
    #endif
    }

    /// UIテスト用: おすすめアップデートを強制（DEBUGのみ・#116）
    static var isUITestUpdateRecommended: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-update-recommended")
    #else
        false
    #endif
    }

    /// UIテスト用: プレイリストを空にする（DEBUGのみ・#160）
    static var isUITestResetPlaylists: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-reset-playlists")
    #else
        false
    #endif
    }

    /// UIテスト・スクリーンショット用: 自分の音（取り込み音）を空にする（DEBUGのみ・#183）
    static var isUITestResetSounds: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-reset-sounds")
    #else
        false
    #endif
    }

    /// UIテスト・スクリーンショット用: ライブラリのサンプルを入れる（DEBUGのみ・#160）
    static var isUITestSeedLibrary: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-seed-library")
    #else
        false
    #endif
    }

    /// UIテスト用: メールが使えない端末として共有シートを開く（#255）
    static var isUITestContactNoMail: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-contact-no-mail")
    #else
        false
    #endif
    }

    /// UIテスト用: 小さい音声の取り込み（#224）
    static var isUITestQuietCrop: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-quiet-crop")
    #else
        false
    #endif
    }

    /// UIテスト用: ミュージックライブラリの曲を選んだあとの切り取り画面（#245）
    static var isUITestMusicCrop: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-music-crop")
    #else
        false
    #endif
    }

    /// UIテスト・スクショ用: ミュージックの「取り込めません」1行を出す（#245）
    static var isUITestMusicUnavailable: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-music-unavailable")
    #else
        false
    #endif
    }

    /// UIテスト・スクショ用: ミュージックの許可がないときの1行を出す（#245 レビュー）
    static var isUITestMusicPermissionDenied: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-music-permission-denied")
    #else
        false
    #endif
    }

    /// UIテスト用: 初めての1回きりアラームが鳴って止まった状態を作る（#247）
    static var isUITestSeedFirstAlarmFollowup: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-seed-first-followup")
    #else
        false
    #endif
    }

    /// UIテスト用: 無音の音を使ったアラームを1本入れる（#256）
    static var isUITestSeedSilentAlarm: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-seed-silent-alarm")
    #else
        false
    #endif
    }

    /// UIテスト・スクショ用: 寝過ごし防止がスヌーズより先に鳴るアラーム（#211 レビュー）
    static var isUITestSeedBackupWarning: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-seed-backup-warning")
    #else
        false
    #endif
    }

    /// UIテスト用: 無音の音声の取り込み（#256）
    static var isUITestSilentCrop: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-silent-crop")
    #else
        false
    #endif
    }

    /// UIテスト用: 一部だけ無音の音声の取り込み（#256 レビュー）
    static var isUITestPartialSilentCrop: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-partial-silent-crop")
    #else
        false
    #endif
    }

    /// 既存アラームの無音判定キャッシュ（ファイル名 → level）。#256 レビュー
    private static let silentAlarmScanCacheKey = "silent_alarm_scan_cache_v1"

    static var silentAlarmScanCache: [String: String] {
        get {
            UserDefaults.standard.dictionary(forKey: silentAlarmScanCacheKey)
                as? [String: String] ?? [:]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: silentAlarmScanCacheKey)
        }
    }

    /// UIテスト用: 取り込んだ音が2つある状態（#207 の提案行）
    static var isUITestSeedSuggestion: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-seed-suggestion")
    #else
        false
    #endif
    }

    /// ストアのスクリーンショット用: 取り込んだ音4つとプレイリストを入れる（DEBUGのみ）
    static var isUITestSeedStore: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-seed-store")
    #else
        false
    #endif
    }

    /// UIテスト・スクリーンショット用: 休みの画面確認用（DEBUGのみ・#197）
    static var isUITestSeedSkip: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-seed-skip")
    #else
        false
    #endif
    }

    /// UIテスト・スクリーンショット用: デザイン監査の固定シード（DEBUGのみ・#173）
    static var isUITestSeedDesignAudit: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-seed-design-audit")
    #else
        false
    #endif
    }

    /// UIテスト用: 起動直後にライブラリタブを開く（DEBUGのみ・#160）
    static var isUITestOpenLibrary: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-open-library")
    #else
        false
    #endif
    }

    /// UIテスト用: 新規アラームをオフで保存する（DEBUGのみ・#160）
    /// シミュレータで実際に鳴って SpringBoard が落ちるのを避ける。
    static var isUITestDisableNewAlarm: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-save-alarm-disabled")
    #else
        false
    #endif
    }

    /// UIテスト用: DEBUG時のみ有効なfresh onboarding強制フラグ
    static var isUITestFreshOnboarding: Bool {
#if DEBUG
        return CommandLine.arguments.contains("-uitest-fresh-onboarding")
#else
        return false
#endif
    }

    /// UI テストとして起動されたか（いずれかの -uitest- 引数がある）。DEBUG のみ
    static var isUITestRun: Bool {
#if DEBUG
        CommandLine.arguments.contains { $0.hasPrefix("-uitest-") }
#else
        false
#endif
    }

    /// UIテスト用: 追加画面を直接開く（DEBUGのみ・#122）
    static var isUITestOpenAddAlarm: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-open-add-alarm")
    #else
        false
    #endif
    }

    /// UIテスト用: コントロールセンターの「一覧」から起動した状態（#272）
    static var isUITestControlList: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-control-list")
    #else
        false
    #endif
    }

    /// UIテスト用: コントロールセンターの「追加」から起動した状態（#272）
    static var isUITestControlAdd: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-control-add")
    #else
        false
    #endif
    }

    /// UIテスト用: 編集画面を直接開く（DEBUGのみ・#122）
    static var isUITestOpenEditAlarm: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-open-edit-alarm")
    #else
        false
    #endif
    }

    /// UIテスト用: DEBUG時のみ有効なアラーム一覧シード
    static var isUITestSeedAlarms: Bool {
#if DEBUG
        return CommandLine.arguments.contains("-uitest-seed-alarms")
#else
        return false
#endif
    }

    /// UIテスト用: 朝のアラームを10本並べる（DEBUGのみ・#282）
    static var isUITestSeedMorningAlarms: Bool {
#if DEBUG
        return CommandLine.arguments.contains("-uitest-seed-morning-alarms")
#else
        return false
#endif
    }

    /// UIテスト用: アラームを2本だけ並べる（DEBUGのみ・#282 レビュー）。
    static var isUITestSeedTwoAlarms: Bool {
#if DEBUG
        return CommandLine.arguments.contains("-uitest-seed-two-alarms")
#else
        return false
#endif
    }

    /// UIテスト用: 広告枠を強制表示する（DEBUGのみ・#282 レビュー）。
    static var isUITestForceAdSlot: Bool {
#if DEBUG
        return CommandLine.arguments.contains("-uitest-force-ad-slot")
#else
        return false
#endif
    }

    /// UIテスト・録画用: 追加画面の初期時刻（DEBUGのみ・#282）。
    /// 例: `-uitest-add-time=11:00`
    static var uitestAddAlarmTime: DateComponents? {
#if DEBUG
        guard let argument = CommandLine.arguments.first(where: {
            $0.hasPrefix("-uitest-add-time=")
        }) else { return nil }
        let value = argument.dropFirst("-uitest-add-time=".count)
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else { return nil }
        return DateComponents(hour: hour, minute: minute)
#else
        return nil
#endif
    }

    /// UIテスト用: 共有シートの受け取りを1件 staging に置く（DEBUGのみ・#222）
    static var isUITestSeedShareImportAudio: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-seed-share-import-audio")
    #else
        false
    #endif
    }

    /// UIテスト用: staging を消さずに起動する（DEBUGのみ・#222）
    static var isUITestKeepShareImport: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-keep-share-import")
    #else
        false
    #endif
    }

    /// UIテスト用: オンのアラームを入れる（DEBUGのみ・#206 / #230）。
    /// 時刻の候補と許可バナーの確認に使う。実際の登録は `isUITestSkipAlarmSync` で止める。
    static var isUITestSeedEnabledAlarms: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-seed-enabled-alarms")
    #else
        false
    #endif
    }

    /// UIテスト用: AlarmKit への登録を止める（DEBUGのみ・#206 / #230）
    static var isUITestSkipAlarmSync: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-seed-enabled-alarms")
            || CommandLine.arguments.contains("-uitest-skip-alarm-sync")
    #else
        false
    #endif
    }

    /// UIテスト用: 行の2行目に出す1文をアクセシビリティツリーにも出す（DEBUGのみ・#289）。
    /// 本番では行の accessibilityLabel を変えないため隠している。
    static var isUITestExposeUntilRing: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-expose-until-ring")
    #else
        false
    #endif
    }

    /// UIテスト用: 止まっている行の層をアクセシビリティツリーにも出す（DEBUGのみ・#296）。
    /// 本番の読み上げは行の先頭に状態を足すだけにして、層は隠しておく。
    static var isUITestExposePausedRow: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-expose-paused-row")
    #else
        false
    #endif
    }

    /// スクリーンショット用: 行の1文を長めに保つ（DEBUGのみ・#289）。
    static var isUITestHoldUntilRing: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-hold-until-ring")
    #else
        false
    #endif
    }

    /// UIテスト用: ライブラリ取り込みの着地を再現する（DEBUGのみ・#246）
    static var isUITestLibraryImportLanding: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-library-import-landing")
    #else
        false
    #endif
    }

    /// UIテスト用: アラームを空にする（DEBUGのみ・#246）
    static var isUITestClearAlarms: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-clear-alarms")
    #else
        false
    #endif
    }

    /// スクリーンショット用: 共有直後の受け取り画面を出す（DEBUGのみ・#239）
    static var isUITestShowShareReceipt: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-show-share-receipt")
    #else
        false
    #endif
    }

    /// UIテスト用: 同梱のプリセット音で波形クロップ画面を直接開く（DEBUGのみ・#149）
    static var isUITestOpenWaveformCrop: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-open-waveform-crop")
    #else
        false
    #endif
    }

    /// UIテスト用: 長い音声（120秒）で波形クロップ画面を開く（DEBUGのみ・#303）。
    /// 選択範囲がズーム窓（最大60秒）より広い状態を再現するために使う。
    static var isUITestLongCrop: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-long-crop")
    #else
        false
    #endif
    }

    /// プレイリストの解放を一度でも出したか（#216）。
    static var playlistUnlockShown: Bool {
        get { userDefaults.bool(forKey: "playlistUnlockShown") }
        set { userDefaults.set(newValue, forKey: "playlistUnlockShown") }
    }

    /// 2つ目の取り込みの解放カードを待っているか（#216 / #324）。
    /// アラームが鳴るまで待つため、起動をまたいで残す。
    static var hasPendingPlaylistUnlock: Bool {
        get { userDefaults.bool(forKey: "hasPendingPlaylistUnlock") }
        set { userDefaults.set(newValue, forKey: "hasPendingPlaylistUnlock") }
    }

    /// 初めての1回きりアラームの提案を出し終えたか（#247）。
    static var firstAlarmFollowupHandled: Bool {
        get { userDefaults.bool(forKey: "firstAlarmFollowupHandled") }
        set { userDefaults.set(newValue, forKey: "firstAlarmFollowupHandled") }
    }

    /// 提案を一度でも表示したか（強制終了で「無視」を取りこぼさないため・#247）。
    static var firstAlarmFollowupShown: Bool {
        get { userDefaults.bool(forKey: "firstAlarmFollowupShown") }
        set { userDefaults.set(newValue, forKey: "firstAlarmFollowupShown") }
    }

    /// UIテスト用: プレイリストの解放条件を有効にする（DEBUGのみ・#216）
    static var isUITestPlaylistUnlock: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-playlist-unlock")
    #else
        false
    #endif
    }

    /// スクリーンショット用: 解放シートを直接出す（DEBUGのみ・#216）
    static var isUITestShowPlaylistUnlock: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-show-unlock")
    #else
        false
    #endif
    }

    /// UIテスト用: 取り込んだ音が1つある状態にする（DEBUGのみ・#216）
    static var isUITestSeedOneSound: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-seed-one-sound")
    #else
        false
    #endif
    }

    /// UIテスト用: 1.8.5 より前から音を2つ取り込んでいた状態（#280）
    static var isUITestSeedExistingUnlock: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-seed-existing-unlock")
    #else
        false
    #endif
    }

    /// UIテスト用: 既存の人のうち、取り込んだ音が1つだけの状態（#280）
    static var isUITestSeedExistingUnlockOneSound: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-seed-existing-unlock-one-sound")
    #else
        false
    #endif
    }

    /// UIテスト用: 既存の人のうち、プレイリストが1つある状態（#280）
    static var isUITestSeedExistingUnlockPlaylist: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-seed-existing-unlock-playlist")
    #else
        false
    #endif
    }

    /// UIテスト用: 既存の人のうち、解放カードをすでに見た状態（#280）
    static var isUITestSeedExistingUnlockShown: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-seed-existing-unlock-shown")
    #else
        false
    #endif
    }

    /// UIテスト用: 既存の人の状態に、音を設定したアラームを1本足す（#324）
    static var isUITestSeedExistingUnlockAlarm: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-seed-existing-unlock-alarm")
    #else
        false
    #endif
    }

    /// UIテスト用: 端末内の履歴に「鳴った」記録を1件入れる（#324）
    static var isUITestSeedAlarmFired: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-seed-alarm-fired")
    #else
        false
    #endif
    }

    /// UIテスト用: 端末内の履歴を空にする（#324）
    static var isUITestClearAlarmHistory: Bool {
    #if DEBUG
        CommandLine.arguments.contains("-uitest-clear-alarm-history")
    #else
        false
    #endif
    }

    /// オンボーディングを完了したか（#98）。
    /// 未完了かつアラーム0件・取り込み音源0件の新規インストールにだけオンボを出す。
    /// 既存ユーザーは初回起動時に条件を満たさなければ立てて以後出さない
    static var hasCompletedOnboarding: Bool {
        get { userDefaults.bool(forKey: "has_completed_onboarding") }
        set { userDefaults.set(newValue, forKey: "has_completed_onboarding") }
    }

    /// スヌーズ記録済みの AlarmEntry.ID（App Group 永続化。スヌーズ検知の二重計上防止）
    static var snoozedAlarmEntryIDs: Set<UUID> {
        get {
            guard let data = userDefaults.data(forKey: "snoozed_alarm_entry_ids"),
                  let ids = try? JSONDecoder().decode(Set<UUID>.self, from: data)
            else { return [] }
            return ids
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            userDefaults.set(data, forKey: "snoozed_alarm_entry_ids")
        }
    }

    /// 試しに鳴らしたアラームの記録（#109）。
    /// AlarmStore の外に置き、停止・60秒経過・次回起動時で確実に掃除する。
    static var testAlarmRecords: [TestAlarmRecord] {
        get {
            guard let data = userDefaults.data(forKey: "test_alarm_records"),
                  let records = try? JSONDecoder().decode([TestAlarmRecord].self, from: data)
            else { return [] }
            return records
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            userDefaults.set(data, forKey: "test_alarm_records")
        }
    }

    /// 記録中の試しアラーム ID（テスト・DismissAlarmIntent の照合用）
    static var testAlarmIDs: Set<UUID> {
        Set(testAlarmRecords.map(\.id))
    }

    /// 本体アラームのスヌーズ回数（entryID → 回数・#110）。
    /// 最終アラーム発火時の `snoozes_before` に使う。
    static var snoozeCounts: [UUID: Int] {
        get {
            guard let data = userDefaults.data(forKey: "snooze_counts"),
                  let map = try? JSONDecoder().decode([UUID: Int].self, from: data)
            else { return [:] }
            return map
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            userDefaults.set(data, forKey: "snooze_counts")
        }
    }

    /// 最終アラームで使う音のファイル名（entryID → fileName・#119）。
    /// 停止 Intent が次回分を登録するときに参照する。
    static var backupSoundNames: [UUID: String] {
        get {
            guard let data = userDefaults.data(forKey: "backup_sound_names"),
                  let map = try? JSONDecoder().decode([UUID: String].self, from: data)
            else { return [:] }
            return map
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            userDefaults.set(data, forKey: "backup_sound_names")
        }
    }

    /// 先行公開中に最終アラームを使い始めた権利（#110）。
    /// 正式に有料化した後も無料で使い続けられる。
    static var backupEarlyAccessGranted: Bool {
        get { userDefaults.bool(forKey: "backup_early_access_granted") }
        set { userDefaults.set(newValue, forKey: "backup_early_access_granted") }
    }

    /// 先行公開中にプレイリスト／フェードを使い始めた権利（#151）。
    static var playlistEarlyAccessGranted: Bool {
        get { userDefaults.bool(forKey: "playlist_early_access_granted") }
        set { userDefaults.set(newValue, forKey: "playlist_early_access_granted") }
    }

    /// 通常アラームに登録中の音ファイル名（entryID → fileName・#151）。
    /// プレイリストの掃除で「AlarmKit に登録中のファイル」を消さないために使う。
    static var primarySoundNames: [UUID: String] {
        get {
            guard let data = userDefaults.data(forKey: "primary_sound_names"),
                  let map = try? JSONDecoder().decode([UUID: String].self, from: data)
            else { return [:] }
            return map
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            userDefaults.set(data, forKey: "primary_sound_names")
        }
    }

    /// 通常アラームの次回発火予定日時（entryID → fireDate・#263）。
    /// 1回きりの reconcile で「発火予定時刻」を使うためだけの計測用メタデータ。
    /// スケジュールの判定には使わない。
    static var primaryScheduledFireDates: [UUID: Date] {
        get {
            guard let data = userDefaults.data(forKey: "primary_scheduled_fire_dates"),
                  let map = try? JSONDecoder().decode([UUID: Date].self, from: data)
            else { return [:] }
            return map
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            userDefaults.set(data, forKey: "primary_scheduled_fire_dates")
        }
    }

    /// 通常アラームの登録内容の署名（entryID → signature・#163）。
    /// 同じ署名の `.scheduled` アラームは同期で作り直さない。
    static var primaryAlarmSignatures: [UUID: AlarmScheduleSignature] {
        get {
            guard let data = userDefaults.data(forKey: "primary_alarm_signatures"),
                  let map = try? JSONDecoder().decode(
                      [UUID: AlarmScheduleSignature].self,
                      from: data
                  )
            else { return [:] }
            return map
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            userDefaults.set(data, forKey: "primary_alarm_signatures")
        }
    }

    /// 最終アラーム（寝過ごし防止）の登録内容の署名（entryID → signature・#163）。
    static var backupAlarmSignatures: [UUID: BackupAlarmScheduleSignature] {
        get {
            guard let data = userDefaults.data(forKey: "backup_alarm_signatures"),
                  let map = try? JSONDecoder().decode(
                      [UUID: BackupAlarmScheduleSignature].self,
                      from: data
                  )
            else { return [:] }
            return map
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            userDefaults.set(data, forKey: "backup_alarm_signatures")
        }
    }

    /// 同期の実行記録（最新50件・#163）。
    static var alarmSyncLog: [AlarmSyncLogEntry] {
        get {
            guard let data = userDefaults.data(forKey: "alarm_sync_log"),
                  let log = try? JSONDecoder().decode([AlarmSyncLogEntry].self, from: data)
            else { return [] }
            return log
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            userDefaults.set(data, forKey: "alarm_sync_log")
        }
    }

    /// 停止時に発火分のため延期した、次回シャッフル順の作り直し待ち（#163）。
    static var pendingShuffleRefreshEntryIDs: Set<UUID> {
        get {
            guard let data = userDefaults.data(forKey: "pending_shuffle_refresh_entry_ids"),
                  let ids = try? JSONDecoder().decode(Set<UUID>.self, from: data)
            else { return [] }
            return ids
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            userDefaults.set(data, forKey: "pending_shuffle_refresh_entry_ids")
        }
    }

    /// 最後に停止 Intent が動いた時刻（#163）。
    /// バックグラウンド起動直後の同期を `intent` きっかけとして記録するために使う。
    /// 祝日・休みの設定があるアラームを止めたときの、最後に軽く同期した日（#197）。
    static var lastSkipReconcileDay: String? {
        get { userDefaults.string(forKey: "last_skip_reconcile_day") }
        set { userDefaults.set(newValue, forKey: "last_skip_reconcile_day") }
    }

    static var lastStopIntentAt: Date? {
        get {
            guard userDefaults.object(forKey: "last_stop_intent_at") != nil else { return nil }
            return Date(timeIntervalSince1970: userDefaults.double(forKey: "last_stop_intent_at"))
        }
        set {
            if let newValue {
                userDefaults.set(newValue.timeIntervalSince1970, forKey: "last_stop_intent_at")
            } else {
                userDefaults.removeObject(forKey: "last_stop_intent_at")
            }
        }
    }

    /// プレイリスト一覧（JSON・#151）
    static var playlistsData: Data? {
        get { userDefaults.data(forKey: "playlists") }
        set {
            if let newValue {
                userDefaults.set(newValue, forKey: "playlists")
            } else {
                userDefaults.removeObject(forKey: "playlists")
            }
        }
    }

    /// プレイリストの書き出しキャッシュ（JSON・#151）
    static var playlistRenderCacheData: Data? {
        get { userDefaults.data(forKey: "playlist_render_cache") }
        set {
            if let newValue {
                userDefaults.set(newValue, forKey: "playlist_render_cache")
            } else {
                userDefaults.removeObject(forKey: "playlist_render_cache")
            }
        }
    }

    /// 停止によって取り消した最終アラームの記録（entryID → 停止時刻・#110）。
    /// 次回同期で同じ締め切りを復活させないための抑制に使う。
    static var backupCanceledAt: [UUID: Date] {
        get {
            guard let data = userDefaults.data(forKey: "backup_canceled_at"),
                  let map = try? JSONDecoder().decode([UUID: Date].self, from: data)
            else { return [:] }
            return map
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            userDefaults.set(data, forKey: "backup_canceled_at")
        }
    }

    /// すべてのアラームを休む区間（#197 画面作り直し）。
    /// 押したときにオンだったアラームの ID だけを対象にする。
    static var globalSkip: GlobalSkip? {
        get {
            guard let data = userDefaults.data(forKey: "global_skip"),
                  let skip = try? JSONDecoder().decode(GlobalSkip.self, from: data)
            else { return nil }
            return skip
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                userDefaults.set(data, forKey: "global_skip")
            } else {
                userDefaults.removeObject(forKey: "global_skip")
            }
        }
    }

    /// 前面復帰時にタイムゾーンの変化を検知するための最後の ID（#197）。
    static var lastSkipTimeZone: String? {
        get { userDefaults.string(forKey: "last_skip_time_zone") }
        set { userDefaults.set(newValue, forKey: "last_skip_time_zone") }
    }

    /// 保存済みアラーム（停止 Intent が最終アラームの設定を読むため・#110）
    static var savedAlarmEntries: [AlarmEntry] {
        guard let data = userDefaults.data(forKey: "saved_alarms"),
              let entries = try? JSONDecoder().decode([AlarmEntry].self, from: data)
        else { return [] }
        return entries
    }

    /// ユーザーが削除したプリセットの fileName（再登録防止用・#45 罠1）
    static var dismissedPresetFileNames: Set<String> {
        get {
            guard let data = userDefaults.data(forKey: "dismissed_preset_file_names"),
                  let ids = try? JSONDecoder().decode(Set<String>.self, from: data)
            else { return [] }
            return ids
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            userDefaults.set(data, forKey: "dismissed_preset_file_names")
        }
    }

    /// 前回送信した alarm_permission の状態（#91-2: 状態が変わったときだけ送るための比較用）
    static var lastReportedPermissionStatus: String? {
        get { userDefaults.string(forKey: "last_reported_permission_status") }
        set {
            if let newValue {
                userDefaults.set(newValue, forKey: "last_reported_permission_status")
            } else {
                userDefaults.removeObject(forKey: "last_reported_permission_status")
            }
        }
    }

    /// ベッドサイド時計の配色テーマ（raw文字列・#56）
    static var bedsideColorThemeRaw: String {
        get { userDefaults.string(forKey: "bedside_color_theme") ?? "white" }
        set { userDefaults.set(newValue, forKey: "bedside_color_theme") }
    }

    /// ベッドサイド時計のユーザー設定（JSON・#59）
    static var bedsideSettingsData: Data? {
        get { userDefaults.data(forKey: "bedside_settings") }
        set {
            if let newValue {
                userDefaults.set(newValue, forKey: "bedside_settings")
            } else {
                userDefaults.removeObject(forKey: "bedside_settings")
            }
        }
    }

    /// ベッドサイドモードの初回ヒント表示済みフラグ（#62）
    static var bedsideHintShown: Bool {
        get { userDefaults.bool(forKey: "bedside_hint_shown") }
        set { userDefaults.set(newValue, forKey: "bedside_hint_shown") }
    }

    /// サウンド選択画面のプリセット開閉状態（nil = 未操作・#65）
    static var presetExpandedOverride: Bool? {
        get {
            guard userDefaults.object(forKey: "preset_expanded_override") != nil else { return nil }
            return userDefaults.bool(forKey: "preset_expanded_override")
        }
        set {
            if let newValue {
                userDefaults.set(newValue, forKey: "preset_expanded_override")
            } else {
                userDefaults.removeObject(forKey: "preset_expanded_override")
            }
        }
    }

    /// Share Extensionからの受け渡し用ステージングディレクトリ
    static var stagingDirectory: URL {
        let url = containerURL.appendingPathComponent("Staging", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
