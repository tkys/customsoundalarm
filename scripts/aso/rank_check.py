#!/usr/bin/env python3
"""App Store の検索での順位を、キーワードごとに記録する。

iTunes Search API（itunes.apple.com/search）で検索し、My Sound Alarm が何位に出るかを
CSV に1日1回追記する。App Store アプリの検索結果と完全には一致しないが、順位の上下の目安になる。

使い方:
    python3 scripts/aso/rank_check.py [--keywords scripts/aso/keywords.json] [--out data/aso/ranks.csv]

- 標準ライブラリだけで動く。
- 同じ日付・国・キーワードの行が既にあれば追記しない（何度動かしても重複しない）。
- iTunes Search API の上限（1分あたり約20回）に合わせて、1回ごとに待つ。
- 200位以内に出ない場合、rank は空欄（=圏外）。
"""
import argparse
import csv
import datetime as dt
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

APP_ID = 6760616800
LIMIT = 200
INTERVAL_SECONDS = 3.2
FIELDS = ["date", "country", "group", "term", "rank", "results"]


def search_rank(term: str, country: str) -> tuple[int | None, int]:
    query = urllib.parse.urlencode(
        {"term": term, "entity": "software", "country": country, "limit": LIMIT}
    )
    url = f"https://itunes.apple.com/search?{query}"
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "rank-check/1.0"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.load(resp)
            ids = [r.get("trackId") for r in data.get("results", [])]
            rank = ids.index(APP_ID) + 1 if APP_ID in ids else None
            return rank, len(ids)
        except (urllib.error.URLError, json.JSONDecodeError, TimeoutError) as error:
            if attempt == 2:
                raise RuntimeError(f"{country} {term!r}: {error}") from error
            time.sleep(10 * (attempt + 1))
    raise AssertionError("unreachable")


def existing_keys(path: str) -> set[tuple[str, str, str]]:
    if not os.path.exists(path):
        return set()
    with open(path, newline="", encoding="utf-8") as f:
        return {(r["date"], r["country"], r["term"]) for r in csv.DictReader(f)}


def main() -> int:
    parser = argparse.ArgumentParser()
    here = os.path.dirname(os.path.abspath(__file__))
    parser.add_argument("--keywords", default=os.path.join(here, "keywords.json"))
    parser.add_argument("--out", default="data/aso/ranks.csv")
    parser.add_argument("--date", default=dt.datetime.now(dt.timezone(dt.timedelta(hours=9))).date().isoformat(),
                        help="記録する日付（既定は今日・JST）")
    args = parser.parse_args()

    with open(args.keywords, encoding="utf-8") as f:
        keywords = {k: v for k, v in json.load(f).items() if not k.startswith("_")}

    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    done = existing_keys(args.out)
    new_file = not os.path.exists(args.out)
    written = failed = 0

    with open(args.out, "a", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        if new_file:
            writer.writeheader()
        for country, groups in keywords.items():
            for group, terms in groups.items():
                for term in terms:
                    if (args.date, country, term) in done:
                        continue
                    try:
                        rank, results = search_rank(term, country)
                    except RuntimeError as error:
                        print(f"skip: {error}", file=sys.stderr)
                        failed += 1
                        continue
                    writer.writerow({
                        "date": args.date, "country": country, "group": group,
                        "term": term, "rank": rank if rank else "", "results": results,
                    })
                    f.flush()
                    written += 1
                    print(f"{country}\t{group}\t{term}\t{rank or '-'}")
                    time.sleep(INTERVAL_SECONDS)

    print(f"written={written} failed={failed}", file=sys.stderr)
    return 1 if failed and not written else 0


if __name__ == "__main__":
    sys.exit(main())
