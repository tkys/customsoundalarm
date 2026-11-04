#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <xcresult> [output-dir]" >&2
  exit 1
fi

RESULT="$1"
DEST="${2:-design-audit-output/$(date +%F)}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

xcrun xcresulttool export attachments \
  --path "$RESULT" \
  --output-path "$TMP" >/dev/null

python3 - "$TMP" "$DEST" <<'PY'
import json
import pathlib
import re
import shutil
import sys

src = pathlib.Path(sys.argv[1])
dest = pathlib.Path(sys.argv[2])
dest.mkdir(parents=True, exist_ok=True)

manifest = json.load(open(src / "manifest.json"))
seen = set()
for item in manifest:
    for attachment in item.get("attachments", []):
        name = attachment.get("suggestedHumanReadableName", "")
        match = re.match(r"^(.*)_0_[0-9A-F-]+\.png$", name)
        if not match:
            continue
        base = match.group(1)
        if base in seen:
            continue
        seen.add(base)
        shutil.copy(src / attachment["exportedFileName"], dest / f"{base}.png")

print(f"exported {len(seen)} screenshots to {dest}")
PY

# Keep the repository small without changing colors.
if command -v magick >/dev/null 2>&1; then
  for file in "$DEST"/*.png; do
    magick "$file" -strip -define png:compression-level=9 "$file.tmp"
    mv "$file.tmp" "$file"
  done
fi
