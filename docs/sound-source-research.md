# プリセット音源の調達先調査レポート

作成日: 2026-08-08
Issue: #55

## 背景

Pixabay Content License に「Standalone 配布の禁止（創作的加工なく実質同じ形で配布してはいけない）」条項があり、音そのものが中心的価値である本アプリではグレーが濃い。さらに Pixabay は権利を保証せず「あなたの責任」と明記している。代替調達先を調査した。

---

## 比較表

| サイト | カテゴリ | ①アプリ同梱 | ②Standalone禁止 | ③帰属表示 | ④権利保証 | ⑤商用利用 | ⑥費用 | ⑦素材の質 |
|---|---|---|---|---|---|---|---|---|
| **Freesound (CC0)** | CC0 | ✅ 明示的に許可 | ❌ なし | ❌ 不要 | ❌ 免責（ユーザー責任） | ✅ 可能 | 無料 | 効果音中心・質にばらつき |
| **Freesound (CC-BY)** | CC | ✅ 明示的に許可 | ❌ なし | ✅ 必要 | ❌ 免責 | ✅ 可能 | 無料 | 同上 |
| **CC0 (Creative Commons)** | CC0 | ✅ 明示的に許可 | ❌ なし | ❌ 不要 | ❌ 免責 | ✅ 可能 | 無料 | — (ライセンス枠組み) |
| **Internet Archive** | 混在 | ⚠️ ファイルによる | ⚠️ ファイルによる | ⚠️ ファイルによる | ❌ 免責 | ⚠️ ファイルによる | 無料 | 古い素材が多い |
| **ElevenLabs SFX** | AI | ✅ (Paid User) | ❌ なし | ❌ 不要 | ❌ 免責（ユーザー責任） | ✅ (Paid) / ❌ (Free) | サブスク | 効果音生成・品質良好 |
| **Stable Audio** | AI | ✅ ユーザー所有 | ❌ なし | ❌ 不要 | ❌ 免責（ユーザー責任） | ✅ (Paid) | サブスク | 音楽・効果音・品質良好 |
| **Epidemic Sound** | 有料RF | ⚠️ 確認できず | ⚠️ 確認できず | ⚠️ 確認できず | ⚠️ 確認できず | ✅ | サブスク | 高品質・音楽中心 |
| **Artlist** | 有料RF | ⚠️ 確認できず | ⚠️ 確認できず | ⚠️ 確認できず | ⚠️ 確認できず | ✅ | サブスク | 高品質 |
| **Pixabay** | 無料RF | ⚠️ グレー | ✅ **あり** | ❌ 不要 | ❌ 免責 | ✅ | 無料 | 多数・ばらつきあり |
| **ffmpeg 合成** | 自前 | ✅（オリジナル） | ❌ 該当なし | ❌ 不要 | ✅ **権利リスクゼロ** | ✅ | 無料 | 電子音・単調 |

凡例: ✅=はい / ❌=いいえ / ⚠️=条件付き・確認できず

---

## 推奨3案

### 推奨1: Freesound CC0 音源（最優先）

**理由**: CC0 は「copy, modify, distribute, perform the work, even for commercial purposes, all without asking permission」を明記。Standalone 制限なし。帰属表示不要。法的に最も確立されたパブリックドメイン枠組み。

**リスク**: Freesound は「like all content on the internet, there might be cases where the users of our site are (un)knowingly uploading illegal content」と免責。ユーザーアップロードのため、稀に違法アップロードの可能性がある。ただし CC0 の法的枠組み自体は堅牢で、Pixabay の独自ライセンスより予見可能性が高い。

**手順**: Freesound で "CC0" ライセンスフィルタをかけ、効果音（鳥、ベル、チャイム等）を検索。要ログイン（無料）。

**原文引用** (CC0 1.0 Universal, 確認日 2026-08-08):
> You can copy, modify, distribute and perform the work, even for commercial purposes, all without asking permission.

URL: https://creativecommons.org/publicdomain/zero/1.0/

### 推奨2: ffmpeg 合成の継続・改善（リスクゼロ）

**理由**: 現在の7種はすべて権利リスクゼロ。音色の単調さは、より高度な合成（サイン波以外の波形、エンベロープの工夫、複数音源の重ね合わせ）で改善可能。

**改善案**:
- ノコギリ波・三角波をベースにした温かみのある音色
- リバーブ効果（ffmpeg の `aecho` フィルタ）で空間感を付加
- 複数周波数の和音でリッチな響き

**リスク**: なし（オリジナル作品）

### 推奨3: Stable Audio / ElevenLabs Sound Effects（有料AI生成）

**理由**: どちらも規約で「ユーザーが生成物の権利を保持する」ことを明記。アプリへの同梱・配布に standalone 制限はない。

**Stable Audio** (確認日 2026-08-08):
> Subject to your compliance with our Terms, we assign to you all of our right, title, and interest (if any) in the Outputs. So as between Stability and you, you own the Output (to the extent permitted by applicable law).

URL: https://stability.ai/terms-of-service (Section 4(a))

**ElevenLabs** (確認日 2026-08-08):
> Except as expressly set forth herein, as between you and ElevenLabs, you retain all rights in and to your Output.

URL: https://elevenlabs.io/terms (Section 4(c)(ii))

**リスク**: 両者とも「AS IS」・免責・ユーザーの補償義務（indemnification）。学習データ由来の第三者権利主張リスクは残る。ただし効果音生成は音楽生成（Suno/Udio のようなレコード会社係争対象）よりリスク水準が低い。サブスク解約後の取り扱いは規約上「所有権の移転は取り消されない」と読めるが、明示的ではない。

---

## 推奨しないものと理由

### Pixabay（Standalone 条項）

Issue 本文のとおり。音そのものが中心的価値のアプリで「substantially the same form」の配布はグレー。

**原文** (Pixabay Content License):
> You cannot sell or distribute Content on a Standalone basis. Standalone means where no creative effort has been applied to the Content and it remains in substantially the same form as it exists on our website.

URL: https://pixabay.com/service/license/

### Suno / Udio（音楽生成AI・係争リスク）

レコード会社との著作権侵害訴訟が報じられている。効果音ではなく音楽生成に特化しており、本アプリの用途（アラーム音）には適合しない。学習データ由来の法的リスクが他の効果音生成AIより高い。

### Internet Archive（ライセンスの混在）

ファイルごとにライセンスが異なり、商用利用可否の確認コストが高い。古い素材が多く、アラーム音としての品質に難がある。

---

## 詳細調査メモ

### Freesound（https://freesound.org/）

3種類のライセンスが存在（音源ごとに異なる）:

1. **CC0 (Creative Commons Zero)**: 「you can do pretty much what you want with the sound. You could even sell the sound... but you can't claim you are the author!」
2. **CC-BY (Attribution)**: 帰属表示（クレジット）が必要
3. **CC-BY-NC (NonCommercial)**: 非商用のみ

**FAQ より** (確認日 2026-08-08):
> The content of the Freesound website is uploaded by the users of the site. As per our terms of service our users are required to follow the rules and not upload any copyrighted material. However, like all content on the internet, there might be cases where the users of our site are (un)knowingly uploading illegal content.

URL: https://freesound.org/help/faq/

**評価**: CC0 フィルタを使えば本アプリの要件を満たす。帰属表示不要。ただし違法アップロードのリスクはゼロではない（運営側も免責）。Pixabay の standalone 条項問題は無い。

### ElevenLabs Sound Effects（https://elevenlabs.io/）

**規約 Section 1(c)** (確認日 2026-08-08):
> if you access or use our Services free of charge (such a user, a "Free User"), you may only use the Services for non-commercial purposes; if you access or use our Services through a paid subscription plan (such a user, a "Paid User"), you may use the Services for commercial purposes

**規約 Section 4(c)(ii)**:
> Except as expressly set forth herein, as between you and ElevenLabs, you retain all rights in and to your Output.

**規約 Section 9 (Indemnification)**:
> you will indemnify, defend (at our option), and hold harmless ElevenLabs... from and against any losses, liabilities, claims... arising out of or related to: (a) your access to or use of the Services; (b) the Content...

**規約 Section 10 (Disclaimers)**:
> our Services... are provided "as is" and "as available" without warranties of any kind... ElevenLabs disclaims all warranties... including implied warranties of... non-infringement.

URL: https://elevenlabs.io/terms

**評価**: Paid プランで商用利用・Output の所有権を明記。ただし免責・ユーザー補償義務あり。効果音生成のため音楽生成系より係争リスクは低い。

### Stability AI / Stable Audio（https://stability.ai/）

**規約 Section 4(a)** (確認日 2026-08-08):
> Subject to your compliance with our Terms, we assign to you all of our right, title, and interest (if any) in the Outputs. So as between Stability and you, you own the Output (to the extent permitted by applicable law).

**規約 Section 11**:
> OUR SERVICES ARE PROVIDED "AS IS"... WE AND OUR PROVIDERS EXPRESSLY DISCLAIM ALL WARRANTIES OF... NON-INFRINGEMENT...
> YOU AGREE TO INDEMNIFY, DEFEND, AND HOLD HARMLESS THE STABILITY PARTIES...

URL: https://stability.ai/terms-of-service

**評価**: Stable Audio は音楽・効果音を生成。ユーザーが Output を所有。サブスク制だが、生成済みファイルの所有権は解約後に取り消される規定は見当たらない（ただし明示的ではない）。学習データの透明性は低い。

### Epidemic Sound / Artlist（有料ロイヤリティフリー）

**確認できず**: 両サイトとも JavaScript レンダリングが必要で、規約ページのテキストを取得できなかった。一般的な知見では:

- **Epidemic Sound**: サブスク制。解約後も「既存プロジェクトで使い続けられる（perpetual license）」とされているが、**要ログインで未確認**。
- **Artlist**: サブスク制。同様に perpetual license をうたっているが、**要ログインで未確認**。

これらは音楽ライブラリが中心で、効果音（アラーム音）の品揃えは限定的な可能性がある。

### Openverse（https://openverse.org/）

CC0/BY の検索アグリゲータ。Freesound や Flickr 等の CC ライセンス素材を横断検索できる。ライセンス自体は各ソースの規定に従う。評価軸1（アプリ同梱）はソースごとの CC ライセンスに依存する。

---

## 確認できなかったサイトと理由

| サイト | 理由 |
|---|---|
| Epidemic Sound | JS レンダリング必須・規約ページにアクセスできず |
| Artlist | 同上 |
| Soundstripe | 同上 |
| Storyblocks | 同上 |
| Pond5 | 同上 |
| Envato (AudioJungle) | 同上 |
| Adobe Firefly (音声) | 音声生成機能の存在を確認できず |
| Meta AudioCraft | オープンウェイト配布だが、生成物の商用利用規約の所在を確認できず |
| Suno / Udio | レコード会社係争中のため評価対象外とした |

---

## まとめ

**評価軸1（アプリ同梱の可否）に明確に答えられたサイト**: 5サイト
- Freesound (CC0): ✅ 明示的に許可
- CC0 ライセンス枠組み: ✅ 明示的に許可
- ElevenLabs: ✅ (Paid User 限定)
- Stable Audio: ✅ ユーザー所有
- ffmpeg 合成: ✅ オリジナル

**調査したサイト数**: 15サイト（すべてのカテゴリを含む）

**最終推奨**: Freesound CC0 を第一候補とし、ffmpeg 合成の改善を並行。有料AI生成（Stable Audio / ElevenLabs）は補完的な位置付け。
