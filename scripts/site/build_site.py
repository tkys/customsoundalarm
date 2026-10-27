# -*- coding: utf-8 -*-
"""Build the My Sound Alarm landing page (docs/) for GitHub Pages.

One content dict per language -> one static HTML page per language.
  en -> docs/index.html (also x-default)
  ja -> docs/ja/index.html
  other languages (scripts/site/i18n_pages.py) -> docs/<path>/index.html
Run:  python3 scripts/site/build_site.py
Re-run after editing copy. support.html / privacy.html are not touched.
"""
import html
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from i18n_pages import LOCALES  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "docs")
BASE = "https://tkys.github.io/customsoundalarm/"
APP_ID = "6760616800"
# Point this at a custom product page for web visitors once it exists
# (App Store Connect > Custom Product Pages), e.g. ...?ppid=<id>
APP_STORE_URL = f"https://apps.apple.com/app/id{APP_ID}"
# PostHog project for the website (public "phc_" key). Empty = no tracking.
POSTHOG_KEY = "phc_uuFAFy25bfEjsVPtVzRBdAiy8yyPLi7NB75MGSQeGXEo"
POSTHOG_HOST = "https://us.i.posthog.com"

PAGES = {
    "en": {
        "path": "",
        "html_lang": "en", "og_locale": "en_US", "lang_name": "English", "as_of_fmt": "as of {y}-{m}-{d}",
        "title": "My Sound Alarm: set part of a song or a video's sound as your iPhone alarm",
        "meta": "Set the part of a song you love, or the sound from a video, as your iPhone alarm. Pick it on a waveform and it repeats until you stop it. Scheduled with Apple's AlarmKit (iOS 26), so it rings in Silent mode and when a Focus is on.",
        "badge_alt": "Download on the App Store",
        "hero_title": "Wake up to your favorite part of a song",
        "hero_body": "Choose a chorus from a song file, or the sound from a video, and make it your iPhone alarm. It plays on repeat until you stop it.",
        "req": "Rings in Silent mode and when a Focus is on. For iPhone with iOS\u00a026 or later.",
        "wave_label": "Chorus 0:42–1:12",
        "wave_caption": "Only this part plays, over and over, until you turn it off.",
        "s1_title": "Choose the part",
        "s1_body": "Open an audio file, a recording of your own voice, or a video you saved, and select a range on the waveform. A 20–30 second chorus works well. When it reaches the end, it starts again.",
        "s1_img_alt": "The trim screen: a waveform with a 32-second section selected",
        "s2_title": "Rings in Silent mode",
        "s2_body": "Alarms are scheduled with AlarmKit, the alarm framework Apple added in iOS 26. They appear on the Lock Screen like Clock alarms and ring in Silent mode and when a Focus is on, even with the app closed.",
        "voices_title": "From the App Store",
        "rating_summary": "{count} ratings on the App Store from {regions} countries and regions, {as_of}.",
        "stars_label": "{n} out of 5 stars",
        "voices_note": "Every written review so far, in the reviewer's own words (one shortened to its title). Translations are ours.",
        "faq_title": "Questions",
        "faq": [
            ("How do I set a song as my alarm on iPhone?",
             "The Clock app can play a song from your library, but always from the beginning. With My Sound Alarm, open an audio file (MP3, AAC, WAV or M4A) or a video, select the part you want on the waveform, and save it as the alarm sound."),
            ("Can I use songs from Apple Music or Spotify?",
             "No. Songs from streaming services are protected and can't be imported. You can use audio files saved in the Files app, recordings of your voice, and videos in your photo library."),
            ("Can I use the sound from a video?",
             "Yes. Choose a video from your photo library or the Files app. The app pulls the audio out of the video, and you choose which part plays."),
            ("Is there a 40-second limit, like custom ringtones?",
             "No. Custom iPhone ringtones stop at about 40 seconds. My Sound Alarm takes up to 10 minutes from a video, and long audio files can be imported as they are. A short section works best because it repeats."),
            ("Will it ring in Silent mode, when a Focus is on, or with the app closed?",
             "Yes, as long as you allow alarms for the app when it asks. Alarms are scheduled with Apple's AlarmKit, so the app doesn't need to be running."),
            ("How do I make the alarm louder?",
             "Alarm volume follows Settings > Sounds & Haptics > Ringtone and Alerts. Turn on Change with Buttons to use the volume buttons. The volume in Control Center is for music and videos and doesn't change alarm volume."),
        ],
        "end_title": "Tomorrow morning, wake up to your favorite chorus.",
        "made_by": "Made by tkys, an independent developer in Japan.",
        "footer_support": "Support",
        "footer_privacy": "Privacy Policy",
    },
    "ja": {
        "path": "ja/",
        "html_lang": "ja", "og_locale": "ja_JP", "lang_name": "日本語", "as_of_fmt": "{y}年{m}月{d}日時点",
        "title": "My Sound Alarm｜好きな曲・動画の音を iPhone のアラームに",
        "meta": "好きな曲の好きな部分や動画の音を、iPhone のアラームに。波形で選んだ部分が、止めるまでくり返し鳴ります。iOS 26 の AlarmKit でアラームを登録するので、マナーモードや集中モードでも鳴ります。",
        "badge_alt": "App Store からダウンロード",
        "hero_title": "好きな曲の、好きなところで起きる",
        "hero_body": "曲のいちばん好きな部分や動画の音を、iPhone のアラームに。止めるまで、くり返し鳴ります。",
        "req": "マナーモードや集中モードでも鳴ります。iOS\u00a026 以降の iPhone 向け。",
        "wave_label": "サビ 0:42–1:12",
        "wave_caption": "止めるまで、この部分だけがくり返し鳴ります。",
        "s1_title": "鳴らす部分を選ぶ",
        "s1_body": "音声ファイル、自分で録音した声、保存した動画を開いて、波形の上で範囲を選ぶだけ。サビの20〜30秒がちょうどいい長さです。最後まで鳴ったら、また最初から鳴ります。",
        "s1_img_alt": "切り出し画面：波形の中で33秒ぶんを選んだところ",
        "s2_title": "マナーモードでも鳴る",
        "s2_body": "アラームは、iOS 26 で Apple が用意した AlarmKit で登録します。時計アプリのアラームと同じようにロック画面に表示され、マナーモードや集中モードでも、アプリを閉じていても鳴ります。",
        "voices_title": "App Store のレビュー",
        "rating_summary": "App Store で {regions} の国と地域から {count} 件の評価（{as_of}）。",
        "stars_label": "5 点中 {n} 点",
        "voices_note": "これまでに書かれたレビューを原文のまま載せています（1件はタイトルのみ）。訳は当サイトによるものです。",
        "faq_title": "よくある質問",
        "faq": [
            ("iPhone で好きな曲をアラームにするには？",
             "時計アプリでもライブラリの曲を選べますが、鳴るのは曲の頭からです。My Sound Alarm なら、音声ファイル（MP3・AAC・WAV・M4A）や動画を開いて、波形で好きな部分を選び、アラームの音として保存できます。"),
            ("Apple Music や Spotify の曲は使えますか？",
             "使えません。配信サービスの曲は保護されているため取り込めません。ファイルアプリに保存した音声ファイル、自分で録音した声、写真ライブラリの動画が使えます。"),
            ("動画の音もアラームにできますか？",
             "できます。写真ライブラリやファイルアプリから動画を選ぶと、音声を取り出します。どの部分を鳴らすかも選べます。"),
            ("自作の着信音のような40秒の制限はありますか？",
             "ありません。自作の着信音は約40秒までですが、My Sound Alarm では動画から最長10分、長い音声ファイルもそのまま取り込めます。くり返し鳴るので、短い部分がおすすめです。"),
            ("マナーモードや集中モード、アプリを閉じているときも鳴りますか？",
             "最初に表示される「アラーム」の許可をオンにしていれば鳴ります。Apple の AlarmKit でアラームを登録するので、アプリが起動していなくても鳴ります。"),
            ("アラームの音を大きくするには？",
             "アラームの音量は「設定 → サウンドと触覚 →『着信音と通知音』」で決まります。「ボタンで変更」をオンにすると、本体の音量ボタンでも変えられます。コントロールセンターの音量は音楽や動画の音量で、アラームには効きません。"),
        ],
        "end_title": "明日の朝は、好きなサビで起きる。",
        "made_by": "日本の個人開発者 tkys がつくっています。",
        "footer_support": "サポート",
        "footer_privacy": "プライバシーポリシー",
    },
}

# Written App Store reviews, quoted as written (reviewer names left out).
# "tr" = our translation into the page language; omitted when the review is already in it.
# Only the title of the Spanish review is quoted: its body uses a word we keep off the site.
REVIEWS = [
    {"stars": 5, "cc": "KR", "date": "2026-09", "lang": "en",
     "title": "This app is the goat.",
     "body": "It contains what i really wanted, thank you for creating this app.",
     "tr": {"ja": "最高のアプリ。本当にほしかったものが入っていました。作ってくれてありがとう。"}},
    {"stars": 3, "cc": "FR", "date": "2026-09", "lang": "fr",
     "title": "Enlever les vibrations",
     "body": "Super application qui fonctionne très bien, même en mode avion, ne pas déranger etc Seul bémol il est impossible depuis l’application d’enlever les vibrations ou de les modifier",
     "tr": {"ja": "とてもよく動くアプリ。機内モードやおやすみモードでも鳴ります。唯一の難点は、アプリからバイブレーションを切ったり変えたりできないこと。",
            "en": "A great app that works very well, even in Airplane mode, Do Not Disturb and so on. The one drawback: you can't turn off or change the vibration from the app."}},
    {"stars": 5, "cc": "ES", "date": "2026-08", "lang": "en",
     "title": "Simply what I want for an alarm clock",
     "body": "",
     "tr": {"ja": "目覚ましに求めていたものそのもの"}},
]
COUNTRY = {
    "ja": {"KR": "韓国", "FR": "フランス", "ES": "スペイン"},
    "en": {"KR": "South Korea", "FR": "France", "ES": "Spain"},
}
STOREFRONTS = ("us jp gb ca au de fr es it nl se no dk fi pl cz pt br mx ar cl co kr tw hk cn sg th vn id my ph in "
               "sa ae eg tr ru ua il za nz at ch be ie gr hu ro sk").split()
# Star breakdown from App Store Connect > Ratings and Reviews (all countries and regions).
# The public lookup API lags and has no breakdown, so update this by hand from ASC.
RATINGS_ASC = {"as_of": "2026-10-27", "counts": {5: 54, 4: 7, 3: 2, 2: 0, 1: 2}}
# Used when the App Store can't be reached at build time (2026-10-25).
RATINGS_FALLBACK = {"count": 59, "avg": 4.8, "regions": 20}


def fetch_ratings():
    """Sum star ratings across storefronts so the number on the page is current at build time."""
    import ssl
    import urllib.request
    total = weighted = regions = 0
    try:
        ctx = ssl.create_default_context()
        for cc in STOREFRONTS:
            url = f"https://itunes.apple.com/lookup?id={APP_ID}&country={cc}"
            res = json.load(urllib.request.urlopen(url, timeout=10, context=ctx)).get("results") or []
            n = res[0].get("userRatingCount", 0) if res else 0
            if n:
                total += n
                weighted += n * res[0]["averageUserRating"]
                regions += 1
    except Exception as e:  # offline, TLS, rate limit
        print("ratings: using fallback,", e)
        return RATINGS_FALLBACK
    return {"count": total, "avg": round(weighted / total, 1), "regions": regions} if total else RATINGS_FALLBACK


def stars(n):
    return "★" * n + "☆" * (5 - n)


def reviews_html(lang, c, r):
    items = []
    for v in REVIEWS:
        tr = v["tr"].get(lang) or c.get("review_tr", {}).get(v["cc"])
        if v["lang"] == c["html_lang"].split("-")[0]:
            tr = None  # already in the page language
        original = f'<b>{esc(v["title"])}</b>' + (f'<br>{esc(v["body"])}' if v["body"] else "")
        # dir=auto: a Latin-script review keeps its own direction inside an RTL page
        quote = f'<p class="orig" lang="{v["lang"]}" dir="auto">{original}</p>'
        if tr:
            quote += f'<p class="tr">{esc(tr)}</p>'
        country = COUNTRY.get(lang, {}).get(v["cc"]) or c["countries"][v["cc"]]
        meta = f'{country} · {v["date"]}'
        items.append(f'<li><span class="stars" aria-label="{c["stars_label"].format(n=v["stars"])}">{stars(v["stars"])}</span>'
                     f'<span class="rmeta">{esc(meta)}</span>{quote}</li>')
    counts = RATINGS_ASC["counts"]
    total = sum(counts.values())
    avg = sum(k * v for k, v in counts.items()) / total
    top = max(counts.values())
    bars = "".join(
        f'<div class="bar"><span class="bl" aria-hidden="true">{"★" * k}</span>'
        f'<span class="bt"><span class="bf" style="width:{counts[k] / top * 100:.1f}%"></span></span>'
        f'<span class="bn">{counts[k]}</span></div>'
        for k in (5, 4, 3, 2, 1)
    )
    y, m, d = RATINGS_ASC["as_of"].split("-")
    as_of = c["as_of_fmt"].format(y=int(y), m=int(m), d=int(d))
    summary = c["rating_summary"].format(count=total, regions=r["regions"], as_of=as_of)
    score = (f'<div class="score" role="img" aria-label="{esc(c["stars_label"].format(n=f"{avg:.1f}"))}">'
             f'<div class="big">{avg:.1f}</div><div class="bigstars" aria-hidden="true">★★★★★</div></div>')
    return (f'<section class="voices"><h2>{esc(c["voices_title"])}</h2>'
            f'<div class="rating">{score}<div class="bars">{bars}</div></div>'
            f'<p class="rsum">{esc(summary)}</p>'
            f'<ul>{"".join(items)}</ul><p class="note">{esc(c["voices_note"])}</p></section>')


PAGES.update(LOCALES)
for _c in PAGES.values():
    _c.setdefault("dir", "ltr")

CSS = """
:root{color-scheme:light;--text:#1C1714;--muted:#5E5650;--line:#E7E2DD;--accent:#FF843B;--ink:#4A1A6B;--wave:#D6D1CC}
/* App colors: orange (AccentColor) is for graphics only — 2.4:1 on white is too low for text; text accents use the icon's purple. */
*{box-sizing:border-box}html{-webkit-text-size-adjust:100%}
body{margin:0;background:#fff;color:var(--text);font:18px/1.7 -apple-system,BlinkMacSystemFont,"Hiragino Sans","Noto Sans JP",sans-serif}
a{color:var(--ink);text-underline-offset:3px}
.wrap{max-width:720px;margin:0 auto;padding:0 20px}
header{display:flex;justify-content:space-between;align-items:center;padding:18px 0 8px;font-size:16px}
.brand{display:flex;align-items:center;gap:10px;font-weight:600;text-decoration:none;color:var(--text)}
.brand img{width:32px;height:32px;border-radius:8px}
h1,h2,h3{word-break:auto-phrase;text-wrap:balance}
.ph{display:inline-block}
p,li{word-break:auto-phrase}
:lang(ko) h1,:lang(ko) h2,:lang(ko) h3,:lang(ko) p{word-break:keep-all}
h1{font-size:clamp(32px,6.4vw,48px);line-height:1.2;letter-spacing:-.015em;margin:36px 0 14px}
.lead{font-size:20px;color:var(--muted);margin:0 0 24px;max-width:34em}
.badge img{height:52px;width:auto;display:block}
.req{font-size:15px;color:var(--muted);margin:10px 0 0}
figure{margin:44px 0 8px}
.wavebox{position:relative;padding-bottom:26px;direction:ltr}
.wave{display:block;width:100%;height:auto}
.wavelabel{position:absolute;bottom:0;transform:translateX(-50%);white-space:nowrap;font-size:14px;font-weight:600;color:var(--ink)}
figcaption{font-size:16px;color:var(--muted);margin-top:8px}
h2{font-size:26px;line-height:1.35;margin:56px 0 10px}
.shot{display:block;width:100%;max-width:340px;height:auto;border:1px solid var(--line);border-radius:22px;margin:18px 0 0}
.side{float:inline-end;width:132px;height:auto;margin-block:0 12px;margin-inline:20px 0}
.clear{clear:both}
h3{font-size:19px;line-height:1.4;margin:30px 0 6px}
.faq p{margin:0;color:var(--muted)}
.end{margin:64px 0 0;padding-top:32px;border-top:1px solid var(--line);display:flex;gap:28px;align-items:center}
.end h2{margin:0 0 18px}
.end-art{width:180px;height:auto;flex:none}
@media (max-width:560px){.end{flex-direction:column;align-items:flex-start}.end-art{width:220px}}
.voices ul{list-style:none;margin:18px 0 0;padding:0}
.voices li{padding:16px 0;border-top:1px solid var(--line)}
.stars{color:var(--accent);letter-spacing:.08em;margin-right:10px}
.rmeta{font-size:15px;color:var(--muted)}
.voices p{margin:6px 0 0}
.voices .tr{color:var(--muted);font-size:16px}
.rsum{margin:8px 0 0;color:var(--muted);font-size:15px}
.rating{display:flex;gap:28px;align-items:center;margin:16px 0 0}
.score{text-align:center;flex:none}
.big{font-size:56px;font-weight:700;line-height:1;letter-spacing:-.02em}
.bigstars{color:var(--accent);letter-spacing:.1em;margin-top:6px}
.bars{flex:1;max-width:360px}
.bar{display:flex;align-items:center;gap:10px;font-size:13px;line-height:1.6}
.bl{width:5.5em;text-align:end;color:var(--muted);letter-spacing:.02em;font-size:11px}
.bt{flex:1;height:6px;background:var(--line);border-radius:3px;overflow:hidden}
.bf{display:block;height:100%;background:var(--accent);border-radius:3px}
.bn{width:2em;color:var(--muted);text-align:end}
.note{font-size:14px;color:var(--muted);margin-top:12px}
.langs{margin:40px 0 0;padding-top:20px;border-top:1px solid var(--line);display:flex;flex-wrap:wrap;gap:6px 16px;font-size:15px}
.langs a[aria-current]{color:var(--text);text-decoration:none;font-weight:600}
footer{padding:28px 0 56px;font-size:15px;display:flex;gap:8px 20px;flex-wrap:wrap}
.made{color:var(--muted);flex-basis:100%}
"""


def esc(s):
    return html.escape(s, quote=True)


def phrases(s):
    """Keep each comma-separated phrase on one line where it fits (Japanese headings)."""
    parts = s.split("、")
    return "".join(f'<span class="ph">{esc(p)}{"、" if i < len(parts) - 1 else ""}</span>' for i, p in enumerate(parts))


def badge(c, img, position):
    return (f'<a class="badge" href="{APP_STORE_URL}" data-pos="{position}" rel="noopener">'
            f'<img src="{img}app-store-badge.svg" alt="{esc(c["badge_alt"])}" width="156" height="52"></a>')


def waveform_svg(c):
    """The page's one signature element: a song as a waveform, with the chorus lit."""
    import math
    n, w, h = 96, 720, 120
    gap = w / n
    lo, hi = 52, 70
    bars = []
    for i in range(n):
        t = i / n
        amp = 0.28 + 0.22 * math.sin(t * 9.1) ** 2 + 0.18 * abs(math.sin(t * 37.3)) + 0.12 * math.sin(t * 3.2 + 1) ** 2
        if lo <= i < hi:
            amp = min(0.98, amp + 0.25)
        bh = max(6, amp * (h - 36))
        x = i * gap + gap * 0.18
        y = (h - 30 - bh) / 2
        color = "var(--accent)" if lo <= i < hi else "var(--wave)"
        bars.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{gap * 0.64:.1f}" height="{bh:.1f}" rx="{gap * 0.32:.1f}" fill="{color}"/>')
    x0, x1 = lo * gap, hi * gap
    line = f'<line x1="{x0:.1f}" y1="{h - 22}" x2="{x1:.1f}" y2="{h - 22}" stroke="var(--ink)" stroke-width="2"/>'
    svg = (f'<svg class="wave" viewBox="0 0 {w} {h - 18}" role="img" aria-label="{esc(c["wave_caption"])}">'
           + "".join(bars) + line + "</svg>")
    # The label is HTML, not SVG text, so it doesn't shrink with the waveform on phones.
    mid = (x0 + x1) / 2 / w * 100
    return f'<div class="wavebox">{svg}<span class="wavelabel" style="left:{mid:.1f}%">{esc(c["wave_label"])}</span></div>'


def jsonld(lang, c):
    url = BASE + c["path"]
    app = {
        "@context": "https://schema.org",
        "@type": "SoftwareApplication",
        "name": "My Sound Alarm",
        "alternateName": "CustomSoundAlarm",
        "operatingSystem": "iOS 26.0 or later",
        "applicationCategory": "UtilitiesApplication",
        "description": c["meta"],
        "url": url,
        "downloadUrl": APP_STORE_URL,
        "sameAs": APP_STORE_URL,
        "image": BASE + "assets/img/icon.png",
        "screenshot": BASE + ("assets/img/crop-ja.jpg" if lang == "ja" else "assets/img/crop-en.jpg"),
        "author": {"@type": "Person", "name": "tkys", "url": "https://github.com/tkys"},
    }
    faq = {
        "@context": "https://schema.org",
        "@type": "FAQPage",
        "inLanguage": c["html_lang"],
        "mainEntity": [
            {"@type": "Question", "name": q,
             "acceptedAnswer": {"@type": "Answer", "text": a}}
            for q, a in c["faq"]
        ],
    }
    return "\n".join(
        f'<script type="application/ld+json">{json.dumps(o, ensure_ascii=False)}</script>'
        for o in (app, faq)
    )


def analytics(lang):
    if not POSTHOG_KEY:
        return ""
    # Cookieless: in-memory persistence, no session recording, so no consent banner is needed.
    # Only on the published site, so local/LAN previews never reach PostHog.
    return f"""<script>
// Owner opt-out: open the page once with ?internal=1 on each of your devices (?internal=0 to undo).
var csaInternal=false;try{{var q=new URLSearchParams(location.search).get("internal");if(q==="1")localStorage.setItem("csa_internal","1");if(q==="0")localStorage.removeItem("csa_internal");csaInternal=localStorage.getItem("csa_internal")==="1";}}catch(e){{}}
if(location.hostname==="tkys.github.io"&&!csaInternal){{
!function(t,e){{var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){{function g(t,e){{var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){{t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}}}(p=t.createElement("script")).type="text/javascript",p.crossOrigin="anonymous",p.async=!0,p.src=s.api_host.replace(".i.posthog.com","-assets.i.posthog.com")+"/static/array.js",(r=t.getElementsByTagName("script")[0]).parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){{var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e}},u.people.toString=function(){{return u.toString(1)+".people (stub)"}},o="init capture register register_once unregister opt_out_capturing has_opted_out_capturing opt_in_capturing reset".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])}},e.__SV=1)}}(document,window.posthog||[]);
posthog.init("{POSTHOG_KEY}",{{api_host:"{POSTHOG_HOST}",persistence:"memory",person_profiles:"identified_only",disable_session_recording:true,capture_pageview:true}});
posthog.register({{site_lang:"{lang}"}});
document.addEventListener("click",function(e){{var a=e.target.closest("a.badge");if(a)posthog.capture("app_store_link_clicked",{{position:a.dataset.pos||""}});}});
}}
</script>"""


def redirect_script():
    """On the English root only: send first-time visitors to their browser language.

    - Only when someone lands on the root directly. A ?lang=… link from our own language
      list, or arriving from another page of this site, keeps them where they chose.
    - Nothing is stored on the device. Crawlers read each language page directly (hreflang).
    - Relative paths, so local previews stay local; query/hash are kept (?internal=1 etc.).
    """
    targets = {
        o["html_lang"].split("-")[0].lower(): o["path"]
        for o in PAGES.values() if o["path"] and o["html_lang"] != "zh-Hans"
    }
    return """<script>
(function(){try{
var q=new URLSearchParams(location.search);if(q.has("lang"))return;
if(document.referrer&&new URL(document.referrer).pathname.indexOf(location.pathname)===0&&new URL(document.referrer).host===location.host)return;
var map=%s,ls=navigator.languages||[navigator.language];
for(var i=0;i<ls.length;i++){var t=(ls[i]||"").toLowerCase();
if(t.indexOf("en")===0)return;
if(t.indexOf("zh")===0){if(t==="zh-cn"||t==="zh-sg"||t.indexOf("zh-hans")===0){location.replace("zh-hans/"+location.search+location.hash);}return;}
var k=t.split("-")[0];if(map[k]){location.replace(map[k]+location.search+location.hash);return;}}
}catch(e){}})();
</script>""" % json.dumps(targets)


def page(lang, c, ratings):
    prefix = "../" if c["path"] else ""
    # Language list in the footer; the root link carries ?lang so the redirect below leaves it alone
    langs = " ".join(
        f'<a href="{BASE + o["path"]}{"?lang=en" if not o["path"] else ""}" hreflang="{o["html_lang"]}" lang="{o["html_lang"]}"'
        f'{" aria-current=page" if l == lang else ""}>{esc(o["lang_name"])}</a>'
        for l, o in PAGES.items()
    )
    shot = "crop-ja.jpg" if lang == "ja" else "crop-en.jpg"  # the app UI is English outside Japanese
    img = f"{prefix}assets/img/"
    alts = "\n".join(
        f'<link rel="alternate" hreflang="{PAGES[l]["html_lang"]}" href="{BASE + PAGES[l]["path"]}">'
        for l in PAGES
    ) + f'\n<link rel="alternate" hreflang="x-default" href="{BASE}">'
    faqs = []
    for q, a in c["faq"]:
        faqs.append(f"<h3>{esc(q)}</h3><p>{esc(a)}</p>")
    return f"""<!doctype html>
<html lang="{c["html_lang"]}" dir="{c["dir"]}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light">
<title>{esc(c["title"])}</title>
<meta name="description" content="{esc(c["meta"])}">
<link rel="canonical" href="{BASE + c["path"]}">
{alts}
<meta property="og:title" content="{esc(c["title"])}">
<meta property="og:description" content="{esc(c["meta"])}">
<meta property="og:image" content="{BASE}assets/img/hero.jpg">
<meta property="og:type" content="website">
<meta property="og:url" content="{BASE + c["path"]}">
<meta property="og:site_name" content="My Sound Alarm">
<meta property="og:locale" content="{c["og_locale"]}">
{redirect_script() if lang == "en" else ""}
<meta name="twitter:card" content="summary_large_image">
<link rel="apple-touch-icon" href="{img}icon.png">
<meta name="apple-itunes-app" content="app-id={APP_ID}">
<link rel="icon" href="{img}icon.png">
<style>{CSS}</style>
{jsonld(lang, c)}
</head>
<body>
<div class="wrap">
<header><a class="brand" href="{BASE + c["path"]}"><img src="{img}icon.png" alt="">My Sound Alarm</a>
<a href="#languages">{esc(c["lang_name"])} ▾</a></header>
<main>
<h1>{phrases(c["hero_title"])}</h1>
<p class="lead">{esc(c["hero_body"])}</p>
{badge(c, img, "hero")}
<p class="req">{esc(c["req"])}</p>
<figure>{waveform_svg(c)}<figcaption>{esc(c["wave_caption"])}</figcaption></figure>
<h2>{esc(c["s1_title"])}</h2>
<p>{esc(c["s1_body"])}</p>
<img class="shot" src="{img}{shot}" alt="{esc(c["s1_img_alt"])}" width="340" height="383">
<h2>{esc(c["s2_title"])}</h2>
<img class="side" src="{img}silent.jpg" alt="" width="132" height="132" loading="lazy">
<p>{esc(c["s2_body"])}</p>
<div class="clear"></div>
{reviews_html(lang, c, ratings)}
<section class="faq"><h2>{esc(c["faq_title"])}</h2>{"".join(faqs)}</section>
<section class="end"><img class="end-art" src="{img}hero.jpg" alt="" width="420" height="560" loading="lazy">
<div><h2>{phrases(c["end_title"])}</h2>{badge(c, img, "bottom")}</div></section>
</main>
<nav id="languages" class="langs" aria-label="Language">{langs}</nav>
<footer><span class="made">{esc(c["made_by"])}</span><a href="{prefix}support.html">{esc(c["footer_support"])}</a><a href="{prefix}privacy.html">{esc(c["footer_privacy"])}</a></footer>
</div>
{analytics(lang)}
</body>
</html>
"""


def sitemap():
    urls = []
    for l, c in PAGES.items():
        alts = "".join(
            f'<xhtml:link rel="alternate" hreflang="{PAGES[o]["html_lang"]}" href="{BASE + PAGES[o]["path"]}"/>'
            for o in PAGES
        )
        urls.append(f"<url><loc>{BASE + c['path']}</loc>{alts}</url>")
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" '
            'xmlns:xhtml="http://www.w3.org/1999/xhtml">\n' + "\n".join(urls) + "\n</urlset>\n")


BANNED = ["free", "無料", "必ず", "絶対", "guarantee",
          "gratuit", "kostenlos", "gratis", "gratuito", "gratuita", "gratuitamente",
          "무료", "免费", "darmow", "za darmo", "zdarma", "bezplat", "مجان",
          "toujours garanti", "garantiert", "garantizado", "garantido", "garantito", "gegarandeerd",
          "보장", "保证", "gwarantowan", "zaručen", "مضمون"]


def main():
    ratings = fetch_ratings()
    print("ratings:", ratings)
    quoted = json.dumps([[v["title"], v["body"], v["tr"]] for v in REVIEWS], ensure_ascii=False).lower()
    assert not [w for w in BANNED if w in quoted], "banned word in quoted reviews"
    for lang, c in PAGES.items():
        text = json.dumps(c, ensure_ascii=False).lower()
        bad = [w for w in BANNED if w in text]
        assert not bad, f"{lang}: banned words {bad}"
        out = os.path.join(ROOT, c["path"], "index.html")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with open(out, "w", encoding="utf-8") as f:
            f.write(page(lang, c, ratings))
        print("wrote", os.path.relpath(out, ROOT))
    with open(os.path.join(ROOT, "sitemap.xml"), "w", encoding="utf-8") as f:
        f.write(sitemap())
    print("wrote sitemap.xml")


if __name__ == "__main__":
    main()
