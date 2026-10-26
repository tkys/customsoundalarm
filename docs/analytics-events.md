# 計測イベント仕様（1.8.0）

このアプリが PostHog に送るイベントとユーザープロパティの仕様です。
**イベント名は過去データと続けて比較するため変更しません。** PII（氏名・メール・ファイル名・アラームのラベル文字列など）は送りません。

- `App closed?` = **届く** は、アプリが閉じていても `AlarmEventBuffer`（App Group）に積まれ、次回起動時に送信されるもの。
- `アプリ動作中のみ` は、画面操作・状態監視（`AlarmKit` の `alarmUpdates`）で送られるもの。
- `起動時にも補完` は、監視に加えて `reconcileOnLaunch` でも検出するもの。

## イベント

| イベント名 | プロパティ（型） | 送るタイミング | 答えたい問い | App closed? | 追加版 |
| --- | --- | --- | --- | --- | --- |
| `alarm_created` | `has_custom_sound` bool, `is_repeating` bool, `snooze_minutes` int, `backup_minutes` int（オフは0）, `hours_until` int（任意） | アラーム新規作成時 | 作成行動・寝過ごし防止の利用率 | アプリ動作中のみ | 既存（`backup_minutes` は1.8.0） |
| `alarm_edited` | `has_custom_sound` bool, `is_repeating` bool, `snooze_minutes` int, `backup_minutes` int（オフは0）, `was_enabled` bool, `hours_until` int（任意） | アラーム編集保存時 | 編集で自動オンにした割合 | アプリ動作中のみ | 既存（`backup_minutes`/`was_enabled` は1.8.0） |
| `alarm_deleted` | — | アラーム削除時 | 離脱・整理行動 | アプリ動作中のみ | 既存 |
| `alarm_duplicated` | — | アラーム複製時 | 複製の利用 | アプリ動作中のみ | 既存 |
| `alarm_permission` | `status` string（authorized/denied/not_determined/request_failed/unknown） | 権限状態が変わったとき（永続化比較） | 許可率・拒否の影響 | アプリ動作中のみ | 既存 |
| `alarm_fired` | `was_app_foreground` bool, `hour` int, `is_repeating` bool, `detection` string（observer/reconcile） | アラーム発火検知 | 実際に鳴ったか | アプリ動作中／起動時にも補完 | 既存 |
| `alarm_stopped` | `hour` int | 本体アラームの停止（Intent） | 停止行動 | **届く** | 既存 |
| `alarm_snoozed` | `from` string（observer/reconcile） | スヌーズ待機への遷移 | スヌーズ行動 | アプリ動作中／起動時にも補完 | 既存 |
| `test_ring_scheduled` | `kind` string（own/backup）, `has_backup` bool | 「今すぐ鳴らす」「寝過ごし防止の音を試す」の登録成功時 | 試し鳴らしの利用率 | アプリ動作中のみ | 1.8.0（`has_backup` も1.8.0） |
| `test_ring_stopped` | `hour` int | 試し鳴らしの停止（Intent） | 試し鳴らしの完了率 | **届く** | 1.8.0 |
| `backup_alarm_enabled` | `minutes` int | 寝過ごし防止をオンにして保存 | 寝過ごし防止の採用率 | アプリ動作中のみ | 1.8.0 |
| `backup_alarm_disabled` | `minutes` int（オフにする前の値） | 寝過ごし防止をオフにして保存 | 解除率 | アプリ動作中のみ | 1.8.0 |
| `backup_alarm_fired` | `snoozes_before` int（不明なら省略） | 寝過ごし防止の鳴動を監視で検知 | **補助指標**（アプリが開いていた場合のみ） | アプリ動作中のみ | 1.8.0 |
| `backup_alarm_stopped` | `minutes` int, `snoozes_before` int（不明なら省略）, `hour` int | 寝過ごし防止が鳴って停止された（Intent） | **主指標**: 実際に人を起こした回数・人数、スヌーズ回数 | **届く** | 1.8.0 |
| `backup_alarm_cancelled_by_stop` | — | 本体停止で寝過ごし防止が取り消された（Intent） | 締め切り前に止められた割合 | **届く** | 1.8.0 |
| `backup_loud_variant_generated` | `gain_db_bucket` string, `duration_bucket` string, `source` string（imported/preset） | 大きくした版の生成成功 | 生成品質・音源種別 | アプリ動作中のみ | 1.8.0 |
| `backup_loud_variant_failed` | `reason` string（unreadable_source/silent_source/render_failed/write_failed/source_missing） | 生成失敗（予備音を使用） | 生成失敗率 | アプリ動作中のみ | 1.8.0 |
| `volume_guide_opened` | `from` string（test_ring） | 音量案内を開いた | 案内の利用率 | アプリ動作中のみ | 1.8.0 |
| `update_prompt_shown` | `kind` string（required/recommended）, `current_build` int, `target_build` int | アップデート案内の表示 | 案内の到達 | アプリ動作中のみ | 1.8.0 |
| `update_prompt_tapped` | `kind` string | 「App Store で更新」タップ | 更新への遷移 | アプリ動作中のみ | 1.8.0 |
| `update_prompt_dismissed` | `kind` string（recommended） | おすすめを「あとで」/スワイプで閉じた | おすすめの受容 | アプリ動作中のみ | 1.8.0 |
| `sound_selected` | `kind` string（imported/preset/default）, `rank_bucket` string（1/2-3/4-10/11+） | サウンド選択で音を選んだ | 音の種類・並び順の影響 | アプリ動作中のみ | 1.8.0 |
| `sound_preview_played` | — | サウンドの試聴 | 試聴行動 | アプリ動作中のみ | 既存 |
| `custom_sound_imported` | `source` string（video/audio）, `peak_db_bucket` string, `gain_db_bucket` string | カスタムサウンド取り込み成功 | 取り込み経路・音量 | アプリ動作中のみ | 既存（音量は1.7.1） |
| `video_import_started` | `source` string（photo_library/file） | 動画取り込み開始 | 動画経路 | アプリ動作中のみ | 既存 |
| `video_import_failed` | `reason` string（安定識別子） | 動画取り込み失敗 | 失敗原因 | アプリ動作中のみ | 既存 |
| `sound_picker_recent_used` | — | **送られなくなった**（#123 で「最近使った」を削除） | （過去データのみ） | — | 既存・1.8.0で停止 |
| `bedside_entered` | `layout` string, `theme` string, `hour` int | ベッドサイドモード開始 | ナイトモード利用 | アプリ動作中のみ | 既存 |
| `bedside_exited` | `duration_bucket` string, `exit_method` string | ベッドサイドモード終了 | 滞在・退出導線 | アプリ動作中のみ | 既存 |
| `bedside_setting_changed` | `setting` string, `value` string/number/bool | ベッドサイド設定変更 | 設定の好み | アプリ動作中のみ | 既存 |
| `onboarding_step_viewed` | `step` string（intro/loop/permission/source） | オンボ各場面の表示 | 離脱位置 | アプリ動作中のみ | 既存 |
| `onboarding_source_selected` | `source` string（video/audio/preset/later） | 音の取得元を選択 | 入口の選択 | アプリ動作中のみ | 既存 |
| `onboarding_completed` | `source` string, `permission_granted` bool | オンボ完了 | 完了率 | アプリ動作中のみ | 既存 |
| `review_requested` | — | OS のレビュー依頼を実行 | レビュー依頼の効果 | アプリ動作中のみ | 既存 |
| `review_request_blocked` | `reason` string（below_threshold/already_requested_version/post_fire） | 依頼が抑制された | 抑制理由 | アプリ動作中のみ | 既存 |

## ユーザープロパティ

起動時（および音源の秒数バックフィル時）に送ります。`first_install_build` は `AppTransaction` が取れたときだけ送ります。

| プロパティ | 型 | 意味 | 追加版 |
| --- | --- | --- | --- |
| `custom_sound_count` | int | 取り込んだ音源の数 | 既存 |
| `alarm_count` | int | アラームの数 | 既存 |
| `first_install_version` | string | 初回インストール時のマーケティングバージョン | 既存 |
| `sound_total_seconds_bucket` | string | 取り込み音源の合計秒数の区分 | 既存 |
| `sound_max_seconds_bucket` | string | 最長の取り込み音源の秒数区分 | 既存 |
| `backup_alarm_count` | int | 寝過ごし防止がオンのアラーム数 | 1.8.0 |
| `backup_early_access` | bool | 先行公開の権利を持っているか | 1.8.0 |
| `first_install_build` | int（取れなければ送らない） | 最初にインストールしたビルド番号（`CFBundleVersion`） | 1.8.0 |
| `is_internal` | bool | DEBUG opt-in の内部利用（PostHog 側で除外） | 既存 |
| `build_type` | string（debug） | DEBUG ビルドの super property | 既存 |

## 主指標と補助指標（寝過ごし防止）

- **主指標**: `backup_alarm_stopped`（Intent 経由・アプリが閉じていても届く）。`minutes` / `snoozes_before` / `hour` で、実際に止められた回数・スヌーズ回数を測る。
- **補助指標**: `backup_alarm_fired`（監視経由・アプリが開いているときだけ）。取りこぼしがあるため、主指標には使わない。
- 採用率: `alarm_created` / `alarm_edited` の `backup_minutes`（0 = オフ）と `backup_alarm_enabled` / `backup_alarm_disabled`。
- 継続比較: ユーザープロパティ `backup_alarm_count` / `backup_early_access` でコホートを分ける。

## 送られなくなったもの（#122 / #123）

- `sound_picker_recent_used`: #123 で「最近使った」セクションを削除したため、**送られなくなりました**（イベント名は互換のため enum に残置）。
- 音の大きさ表示（`loudness_*`）: 専用の計測イベント・プロパティは元々ありません。画面から削除済み。
- オン/オフ切り替え（`alarm_enabled`）: 計測イベントではなく画面文言でした。編集画面から削除済み。
- `test_ring_volume_note`: 画面文言（一度だけの注記）で、計測イベントではありません。削除済み。
