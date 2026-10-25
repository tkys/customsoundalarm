# プライバシーポリシー追記案（広告・1.9.0向け）

> **DRAFT / 未公開**
> このファイルは 1.9.0 で広告 SDK を導入する際に `docs/privacy.html` へ反映するための下書きです。
> このIssue（#111）では公開ページを変更しません。SDK の実際の挙動と Google の現行ドキュメントを
> 導入時に確認し、文言を確定してください。

## 反映方針

- `docs/privacy.html` の「広告トラッカーは使用せず…」の段落を、以下の広告に関する説明に置き換える。
- 英語・日本語の両方を更新する。
- 最終更新日を広告導入日のリリース日に更新する。
- 非パーソナライズ広告のみ。ATT（App Tracking Transparency）ダイアログは出さない。
- PRO（買い切り）では広告を表示しない。
- EEA・英国・スイスでは同意画面（UMP）を出さず、制限付き広告のみを表示する。

## English（追記案）

```html
<p>The App displays ads provided by <strong>Google Mobile Ads (AdMob)</strong> to users of the free version.
Ads are <strong>non-personalized</strong>: the App does not request App Tracking Transparency permission and does
<strong>not</strong> use your activity across other companies' apps or websites to personalize ads.
Google may collect device information (such as device type, operating system, and a device identifier),
approximate location derived from IP address, and ad interaction data to deliver and measure ads.
See <a href="https://policies.google.com/privacy">Google's Privacy Policy</a> and
<a href="https://policies.google.com/technologies/ads">How Google uses information from sites or apps that use our services</a>.</p>
<p>In the EEA, the United Kingdom, and Switzerland, the App shows <strong>limited ads only</strong> and does not
display a consent management prompt. Users who purchase PRO do not see ads.</p>
```

## 日本語（追記案）

```html
<p>本アプリは、無料版のユーザーに対して <strong>Google Mobile Ads（AdMob）</strong> による広告を表示します。
広告は<strong>非パーソナライズ広告</strong>です。ATT（App Tracking Transparency）の許可ダイアログは表示せず、
他社のアプリやウェブサイトにまたがる行動情報を広告のパーソナライズに使用<strong>しません</strong>。
Google は、広告の配信・計測のために、端末の種類・OS・端末識別子などの端末情報、IP アドレスから推定される
おおよその地域、広告の表示・操作に関する情報を取得する場合があります。
詳細は <a href="https://policies.google.com/privacy?hl=ja">Google プライバシー ポリシー</a> および
<a href="https://policies.google.com/technologies/ads?hl=ja">Google のサービスを使用するサイトやアプリから収集した情報の Google による使用</a> をご確認ください。</p>
<p>EEA・英国・スイスでは、同意画面を表示せず<strong>制限付き広告のみ</strong>を表示します。
PRO（買い切り）を購入したユーザーには広告を表示しません。</p>
```

## 確認事項（公開前）

- [ ] Google Mobile Ads SDK のバージョンと、実際に収集されるデータ項目を Google の現行ドキュメントで確認
- [ ] 非パーソナライズ広告のリクエスト設定（SDK の `RequestConfiguration` 等）を実装し、この文言と一致させる
- [ ] EEA・英国・スイスで UMP を出さない構成（limited ads）であることを実機で確認
- [ ] PRO 購入後に広告が表示されないことを確認
- [ ] ATT ダイアログが表示されないこと、`NSUserTrackingUsageDescription` を追加していないことを確認
- [ ] App Store Connect の「App のプライバシー」を `docs/drafts/app-privacy-ads.md` に沿って更新
