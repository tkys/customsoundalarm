# Design audit screenshots

UI 見直し（読みやすさ・配色・操作の簡単さ）用のスクリーンショットです。
アプリの UI は変更せず、固定シードと UI テストだけで撮影しています。

- 撮影日: 2026-11-04
- 画像: `design-audit-output/2026-11-04/`（66枚・.gitignore 対象）
- 条件: ライト／ダーク × ja／en。アラーム一覧と追加・編集は ja ライトの AX5 も。
- ファイル名: `<画面>_<外観>_<言語>_<文字サイズ>.png`
  - 例: `alarm-list_dark_ja_default.png`, `alarm-add-single_light_ja_ax5.png`

## 再撮影

```bash
TEST_RUNNER_DESIGN_AUDIT=1 xcodebuild test \
  -project CustomSoundAlarm.xcodeproj \
  -scheme CustomSoundAlarm \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:CustomSoundAlarmUITests/DesignAuditScreenshotUITests

# 直近の xcresult から design-audit-output/<日付>/ に書き出す
scripts/export-design-audit-screenshots.sh \
  "$(ls -td ~/Library/Developer/Xcode/DerivedData/CustomSoundAlarm-*/Logs/Test/*.xcresult | head -1)" \
  design-audit-output/2026-11-04
```

PNG はリポジトリにコミットしません（`design-audit-output/` は .gitignore 対象）。

テストは `-uitest-seed-design-audit` の固定シード（アラーム3件・プレイリスト2件・
自分の音1件）を使い、外観は DEBUG の `-uitest-force-light` / `-uitest-force-dark`、
文字サイズは `-UIPreferredContentSizeCategoryName` で固定しています。

通常の `xcodebuild test` ではこのテストはスキップされます（撮影に時間がかかるため）。撮るときは上のとおり `TEST_RUNNER_DESIGN_AUDIT=1` を付けてください。
