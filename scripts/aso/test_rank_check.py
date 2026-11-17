"""rank_check.py のテスト（ネットワークを使わない）。

実行: python3 -m unittest scripts/aso/test_rank_check.py
"""
import csv
import json
import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rank_check  # noqa: E402


class FakeResponse:
    def __init__(self, ids):
        self.payload = json.dumps({"results": [{"trackId": i} for i in ids]}).encode()

    def read(self, *args):
        return self.payload

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


class SearchRankTests(unittest.TestCase):
    def test_rank_is_one_based_position(self):
        with mock.patch("urllib.request.urlopen", return_value=FakeResponse([1, 2, rank_check.APP_ID, 4])):
            self.assertEqual(rank_check.search_rank("alarm", "us"), (3, 4))

    def test_missing_app_returns_none(self):
        with mock.patch("urllib.request.urlopen", return_value=FakeResponse([1, 2])):
            self.assertEqual(rank_check.search_rank("alarm", "us"), (None, 2))


class MainTests(unittest.TestCase):
    def run_main(self, keywords, out, date="2026-11-17"):
        argv = ["rank_check.py", "--keywords", keywords, "--out", out, "--date", date]
        with mock.patch.object(sys, "argv", argv), \
             mock.patch.object(rank_check, "search_rank", side_effect=lambda t, c: (5 if t == "a" else None, 100)) as search, \
             mock.patch.object(rank_check.time, "sleep"):
            code = rank_check.main()
        return code, search

    def test_writes_rows_and_skips_duplicates(self):
        with tempfile.TemporaryDirectory() as tmp:
            kw = os.path.join(tmp, "k.json")
            out = os.path.join(tmp, "data", "ranks.csv")
            with open(kw, "w", encoding="utf-8") as f:
                json.dump({"_note": "x", "us": {"big": ["a"], "mid": ["b"]}}, f)

            code, search = self.run_main(kw, out)
            self.assertEqual(code, 0)
            self.assertEqual(search.call_count, 2)
            with open(out, newline="", encoding="utf-8") as f:
                rows = list(csv.DictReader(f))
            self.assertEqual([(r["term"], r["group"], r["rank"]) for r in rows], [("a", "big", "5"), ("b", "mid", "")])

            # 同じ日にもう一度動かしても増えない
            _, search = self.run_main(kw, out)
            self.assertEqual(search.call_count, 0)

            # 翌日は追記される
            _, search = self.run_main(kw, out, date="2026-11-18")
            self.assertEqual(search.call_count, 2)
            with open(out, newline="", encoding="utf-8") as f:
                self.assertEqual(len(list(csv.DictReader(f))), 4)


if __name__ == "__main__":
    unittest.main()
