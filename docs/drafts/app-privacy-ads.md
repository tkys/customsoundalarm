# App Store Connect / Info.plist / PrivacyInfo 広告対応メモ（1.9.0向け）

> **DRAFT / 未公開**
> #111 では広告 SDK を追加しないため、Info.plist と PrivacyInfo.xcprivacy は変更していません。
> SDK 導入時に Google の現行ドキュメントと App Store Connect の表示に合わせて確定してください。

## 1. App Store Connect「App のプライバシー」

広告導入時に見直す項目:

| 区分 | 変更案 | 理由 |
| --- | --- | --- |
| トラッキング（Data Used to Track You） | **なし（No）** | 非パーソナライズ広告のみ。ATT を出さず、他社アプリ/サイト横断のトラッキングをしない |
| お客様に関連付けられるデータ（Data Linked to You） | **なし（No）** | 広告 ID をアカウントや個人情報に紐づけない |
| お客様に関連付けられないデータ（Data Not Linked to You） | **Identifiers → Device ID** | 広告配信・不正防止・計測のため |
| 同上 | **Usage Data → Advertising Data** | 広告の表示・操作 |
| 同上 | **Usage Data → Product Interaction** | 広告の表示機会・操作（アプリ内の匿名イベント） |
| 同上 | **Diagnostics → Crash Data / Performance Data**（SDK が収集する場合） | SDK の仕様を確認して追加 |
| 利用目的 | **Third-Party Advertising** | Google Mobile Ads |
| 既存の PostHog 項目 | 変更なし | 匿名の利用分析 |

- 各データ型の「用途」に Third-Party Advertising を設定する。
- 「トラッキングに使用していますか？」は **いいえ**（ATT なし・非パーソナライズ）。
- 実際の SDK のデータ収集は Google の「データセーフティ」表示と一致させる。

## 2. Info.plist に追加する項目（SDK 導入時）

```xml
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY</string>
```

- `GADApplicationIdentifier` は AdMob のアプリ ID（広告ユニット ID ではない）。
- `SKAdNetworkItems` は Google が公開している現行の ID 一覧をそのまま追加する。
  - 形式:

```xml
<key>SKAdNetworkItems</key>
<array>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>cstr6suwn9.skadnetwork</string>
  </dict>
  <!-- Google の公式リストの残りを追加 -->
</array>
```

- **注意**: SKAdNetwork ID は Google の公式ドキュメントで頻繁に更新される。
  導入時に最新リストを取得し、以後も SDK 更新時に見直す。
- `NSUserTrackingUsageDescription` は **追加しない**（ATT を出さないため）。
- 既存の `NSAlarmKitUsageDescription` / `NSPhotoLibraryUsageDescription` / `NSMicrophoneUsageDescription` は変更なし。

## 3. PrivacyInfo.xcprivacy の確認事項

- [ ] Google Mobile Ads SDK 同梱の `PrivacyInfo.xcprivacy` がアプリにマージされていること
- [ ] `NSPrivacyTracking` が `false` であること
- [ ] `NSPrivacyTrackingDomains` が空であること（トラッキングしない）
- [ ] `NSPrivacyCollectedDataTypes` が ASC の申告と一致すること
      （Device ID / Advertising Data / Product Interaction / Diagnostics 等）
- [ ] `NSPrivacyAccessedAPITypes` に SDK が要求する Required Reason API が含まれていること
      （SDK 側のマニフェストを優先し、アプリ側の既存申告と重複しないこと）
- [ ] App Store Connect の「Third-Party SDKs」で Google Mobile Ads を申告すること
- [ ] プライバシーポリシーの公開版（`docs/privacy.html`）を `docs/drafts/privacy-ads.md` に沿って更新すること

## 4. このIssueで変更しないもの

- `CustomSoundAlarm/Info.plist`（SDK 未導入のため）
- `PrivacyInfo.xcprivacy`（SDK 未導入のため）
- App Store Connect のメタデータ
- `docs/privacy.html`（下書きのみ）
