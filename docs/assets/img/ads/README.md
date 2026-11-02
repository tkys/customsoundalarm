# 広告 SDK の表示確認（#147）

DEBUG ビルドで `AdsConfig.isEnabled` を一時的に true、`-uitest-force-ads-eligible` を付けて、
Google のテスト広告ユニットで撮影したものです。本番の広告ではありません。

- `banner-alarm-list.png`: アラーム一覧下部の適応型バナー
- `banner-import.png`: 音声取り込み画面下部の適応型バナー
- `interstitial.png`: 取り込み保存後の全画面広告

`AdsConfig.isEnabled` はマージ時点で false のままです。
