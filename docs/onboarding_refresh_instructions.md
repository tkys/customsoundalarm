# My Sound Alarm オンボ新設 開発指示書（「好きな瞬間を選ぶだけ」）— v1.7.0 案

## Section 0: エージェントへの注意事項

### コアコンセプト
**「好きな曲の、好きな瞬間で起きる。サビだけ切って、起きるまでくり返し。」**

現状：初回起動するとオンボなしで**いきなり AlarmKit の許可ダイアログ**が出る（価値を見せる前）。その後は空の一覧に「アラームを追加」ボタンだけ。
取り込みまでは 4 タップ（追加 → サウンド → ＋ → 動画/ファイル）。

データ（PostHog 30日・新規 1,027人）：
| 段階 | 通過 |
|---|---|
| 許可ダイアログ表示 | 99.8%（起動直後） |
| 許可 | 90.7%（拒否 8.6%） |
| 動画取り込み開始 | 55.2% |
| アラーム作成 | 83.8% |
| 作成しなかった人の内訳 | 取り込みに手を付けず 117人(11.4%) / 取り込んだが作成せず 27人 / 拒否 19人 |

→ 狙いは2つ。①**価値を見せてから許可を聞く**（拒否 8.6% を下げる）②**最初の1本を「どこから音を持ってくる？」で直接取り込みへ連れていく**（手付かず 11.4% を下げる）。

### 設計原則（RecExport で確定した方針を流用）
1. **テキストは読まれない**。説明文を置かず、イラスト＋見出し1行で伝える。本文テキストは置かない。
2. **「設定」「許可」「インポート」を見出しに使わない**。やりたいこと目線で問う：「どこから音を持ってくる？」
3. **UIモックで操作説明しない**。場面はイラストで「自分の使い方だ」と伝える。
4. **絶対表現（必ず鳴る／100% 等）は使わない**。
5. **オンボ画面はライト表示に固定**（イラストが白背景のため）。
6. **「無料」という言葉を使わない**（マネタイズ方針）。

### 行動原則
- 1 Phase = 1 コミット = ビルドが通る。テスト作成・実行・結果をコミットメッセージに記録。
- **AlarmKit のスケジュール・同期ロジック、音声変換・クロップの中身は変えない**（呼び出し順と入口だけ）。
- 外部ライブラリ追加禁止（アニメーションは SwiftUI 標準）。print 禁止。
- 文言は ja/en 両方の Localizable.strings に追加（行数同数維持・ベタ書き禁止）。en-GB は en を使う。
- `@Environment(\.accessibilityReduceMotion)` が true ならアニメーションを省く。

### やってはいけないこと
- [ ] 既存ユーザー（アラームが1件以上ある／アップデートで来た人）にオンボを出す
- [ ] 許可を「拒否」した人をオンボ内で止める・再度せかす（既存の拒否時の案内に任せる）
- [ ] アプリ内に新しい常設ナッジ・バナーを足す（「大きなお世話」になる）
- [ ] プリセット音源の追加・Pro 機能への誘導をオンボに入れる

---

## Section 1: 素材（オーナーが ChatGPT で生成・白背景・文字なし）
| アセット名 | 場面 | 内容 | 目安比率 |
|---|---|---|---|
| `onboarding_hero` | 場面1 | 朝のベッド。枕元のスマホから音符が流れ、人が気持ちよく伸びをしている | 3:4 |
| `onboarding_loop` | 場面2 | 曲の波形の一部分（サビ）だけが色付きで切り出され、くるっと回る矢印でくり返している | 4:3 |
| `onboarding_silent` | 場面3 | 夜のスマホ。消音スイッチ／月マークがあっても、アラームの音符が出ている | 1:1 |
文字・ロゴ・UIは描き込まない（全ロケール共通で使う）。
**素材はオーナーが後から追加する。** 実装中は `UIImage(named:)` が nil のとき、同じ比率の薄いグレーの角丸枠を表示する（クラッシュ・レイアウト崩れなし）。素材が入ったら差し替え不要で表示されること。`.gitignore` に `*.png` 除外があれば onboarding_* の例外を追加。

## Section 2: 対象ファイル（想定）
```
Views/（新規）OnboardingView.swift          # 場面1〜4
Models/（新規）OnboardingLogic.swift        # 表示判定・ステップ定義（純ロジック）
App/CustomSoundAlarmApp.swift               # 起動時の許可要求をオンボ後へ移す
Views/ContentView.swift                     # オンボの表示、選ばれた入口で追加画面を開く
Views/AddAlarmView.swift / SoundPickerView.swift  # 入口指定で動画/ファイル取り込みを直接開く
Services/AnalyticsService.swift             # 計測追加
Shared/AppGroup.swift                       # hasCompletedOnboarding
Resources/ja.lproj, en.lproj/Localizable.strings
Tests/…
```

---

## Section 3: 実装

### Phase 1：表示判定と許可要求の移動
- `OnboardingLogic.shouldShow(hasCompleted:alarmCount:importedSoundCount:)`：未完了 かつ アラーム0件 かつ 取り込み音源0件 のときだけ true。
  **既存ユーザー**（アップデートで来た人）は、初回起動時に条件を満たさなければ `hasCompletedOnboarding = true` を立てて以後出さない。
- `CustomSoundAlarmApp` の `requestAuthorization()` は、**オンボを出すときは呼ばない**（場面3で呼ぶ）。
  オンボを出さない人は従来どおり起動時に呼ぶ。許可後の `reconcileOnLaunch / syncAlarms / startObservingAlarmStates` は、場面3で許可された時点で同じ順に実行する。

### Phase 2：場面1・2（何ができるか）
**場面1** `onboarding_hero` を画面の約55%。見出し1行：
- ja「好きな曲の、好きな瞬間で起きる」／ en「Wake up to the part you love」
- ボタン ja「次へ」／ en「Next」

**場面2** `onboarding_loop`。見出し1行：
- ja「サビだけ切って、起きるまでくり返し」／ en「Pick the chorus. It plays until you're up.」
- 波形の色付き部分を左→右へ一度だけ塗る程度の軽いアニメーションは可（reduceMotion 時なし）。

### Phase 3：場面3（鳴らすための許可・プライミング）
`onboarding_silent`。見出し1行：
- ja「消音モードでも鳴るように」／ en「So it rings, even on silent」
- ボタン ja「続ける」／ en「Continue」→ ここで `requestAuthorization()`（システムダイアログ）。
- 許可でも拒否でも次の場面4へ進む（止めない・再要求しない）。結果は既存 `alarm_permission` で送られる。
※ 「消音モードでも鳴る」は AlarmKit の挙動。実機で消音スイッチON・集中モードONで鳴ることを受け入れ確認に含める。

### Phase 4：場面4（どこから音を持ってくる？）
見出し：ja「どこから音を持ってくる？」／ en「Where's the sound you love?」
大きな行3つ（行全体がタップ対象・SF Symbol＋短語）：
| 行 | ja | en | タップ後 |
|---|---|---|---|
| 🎬 `video.badge.waveform` | 動画から | From a video | アラーム追加画面を開き、**動画の取り込みシートを直接開く** |
| 📄 `doc.badge.plus` | 音声ファイルから | From an audio file | 追加画面を開き、**ファイル選択を直接開く** |
| 🔔 `bell` | 入っている音で試す | Try a built-in sound | 追加画面を開き、サウンドはプリセット先頭を選択済みにする |
- 控えめなテキストボタン ja「あとで」／ en「Later」→ 一覧へ。
- どれを押してもオンボ完了フラグを立てる。取り込みを途中でキャンセルしても追加画面に戻るだけ（オンボには戻らない）。
- 実装：`AddAlarmView` / `SoundSelectionView` に `initialImport: OnboardingSource?` を渡し、表示直後に該当のシート／fileImporter を1回だけ開く。既存の取り込み処理はそのまま使う。

### Phase 5：計測（PostHog・既存の snake_case に合わせる）
| イベント | プロパティ | タイミング |
|---|---|---|
| `onboarding_step_viewed` | `step`: intro / loop / permission / source | 各場面表示時 |
| `onboarding_source_selected` | `source`: video / audio / preset / later | 場面4 |
| `onboarding_completed` | `source`, `permission_granted` | 完了時 |
既存 `alarm_permission` `video_import_started` `custom_sound_imported` `alarm_created` はそのまま。
指標：**新規の24時間以内のカスタム音源アラーム作成率**（オンボ前のベースラインをリリース前に取る）、許可率、取り込み手付かず率。

### Phase 6：テスト（Swift Testing / XCTest・純ロジック中心）
| テスト | 検証 |
|---|---|
| `testShowsOnlyForFreshInstall` | 未完了×アラーム0×取込0 のときだけ表示 |
| `testExistingUserNeverSeesOnboarding` | アラームか取込音源が1件でもあれば表示せず、完了フラグが立つ |
| `testAuthorizationDeferredWhenOnboarding` | オンボ表示時は起動時に許可要求しない／非表示時は従来どおり要求 |
| `testSourceMapsToInitialImport` | video/audio/preset/later が正しい入口に対応 |
| `testOnboardingKeysExistJaEn` | 追加キーが ja/en 双方にあり行数同数 |
UI・シート表示は実機確認。実行できない場合は「未実行: 理由」を記録。

---

## Section 4: 文言（追加キー）
| キー | ja | en |
|---|---|---|
| `onb.hero.title` | 好きな曲の、好きな瞬間で起きる | Wake up to the part you love |
| `onb.loop.title` | サビだけ切って、起きるまでくり返し | Pick the chorus. It plays until you're up. |
| `onb.silent.title` | 消音モードでも鳴るように | So it rings, even on silent |
| `onb.next` | 次へ | Next |
| `onb.continue` | 続ける | Continue |
| `onb.source.title` | どこから音を持ってくる？ | Where's the sound you love? |
| `onb.source.video` | 動画から | From a video |
| `onb.source.audio` | 音声ファイルから | From an audio file |
| `onb.source.preset` | 入っている音で試す | Try a built-in sound |
| `onb.later` | あとで | Later |

## Section 5: 受け入れ条件（実機）
1. 削除→新規インストール。**ダークモードでもオンボは白**。許可ダイアログはオンボ前に出ない。
2. 場面1→2→3。場面3の「続ける」で初めて許可ダイアログ。許可・拒否どちらでも場面4へ。
3. 場面4「動画から」→ 追加画面の上に動画取り込みが直接開く → 切り出し → 保存でアラーム1件。
4. 別の新規インストールで「音声ファイルから」「入っている音で試す」「あとで」もそれぞれ確認。
5. 許可後、消音スイッチON・集中モードONでもアラームが鳴る。
6. **既存ユーザーにアップデート**してもオンボは出ず、起動時の許可要求も従来どおり。

## Section 6: 環境
xcodegen generate → ビルド → xcodebuild test。ブランチ `feat/onboarding`（worktree で作業し都度 push）。完了時に PR。
