#!/usr/bin/env bash
# Fetch a Cfx depot product into products/<product>/<build>, verifying SHA256.
set -euo pipefail
. "$(dirname "$0")/env.sh"

PROD="${1:?usage: fetch-product.sh <product> [branch]}"
BRANCH="${2:-main}"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
LOCAL="$WINEPREFIX/drive_c/users/$WINE_USER/AppData/Local/FiveM for GTAV Enhanced"
MAN="$FIVEM_ROOT/dl/manifest-$PROD.json"

mkdir -p "$FIVEM_ROOT/dl"
manifest_tmp="$(mktemp "$FIVEM_ROOT/dl/.manifest-$PROD.XXXXXX")"
trap 'rm -f "$manifest_tmp"' EXIT
curl --proto '=https' --proto-redir '=https' -sfL --retry 2 --max-time 90 -A "$UA" -o "$manifest_tmp" \
  "https://depot.cfx.re/public/p/$PROD/u/$BRANCH"
python3 - "$manifest_tmp" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
if not isinstance(data, dict) or not isinstance(data.get("content_files"), list) or not data.get("build"):
    raise SystemExit("Cfx product manifest is missing required fields")
PY
mv -f "$manifest_tmp" "$MAN"
BUILD="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["build"])' "$MAN")"
DEST="$LOCAL/products/$PROD/$BUILD"
mkdir -p "$DEST"
echo "== $PROD branch=$BRANCH build=$BUILD -> products/$PROD/$BUILD"

python3 - "$MAN" <<'PY' | while IFS=$'\t' read -r url rel want; do
import json
import re
import sys
from pathlib import PurePosixPath
from urllib.parse import urlsplit

with open(sys.argv[1], encoding="utf-8") as f:
    manifest = json.load(f)

for item in manifest["content_files"]:
    url = item.get("download_url", "")
    rel = item.get("relative_path", "")
    want = item.get("hash_sha256", "").lower()
    parsed = urlsplit(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise SystemExit(f"Rejected non-HTTPS/invalid Cfx download URL: {url!r}")
    if not rel or "\\" in rel or ":" in rel or any(part in ("", ".", "..") for part in rel.split("/")):
        raise SystemExit(f"Rejected unsafe relative path in Cfx manifest: {rel!r}")
    if PurePosixPath(rel).is_absolute():
        raise SystemExit(f"Rejected absolute path in Cfx manifest: {rel!r}")
    if any(ch in url or ch in rel for ch in ("\t", "\r", "\n")):
        raise SystemExit("Rejected control characters in Cfx manifest")
    if not re.fullmatch(r"[0-9a-f]{64}", want):
        raise SystemExit(f"Rejected invalid SHA256 for {rel!r}")
    print("\t".join((url, rel, want)))
PY
  out_dir="$DEST/$(dirname "$rel")"
  mkdir -p "$out_dir"
  out="$DEST/$rel"
  if [ -f "$out" ] && [ "$(sha256sum "$out" | cut -d' ' -f1)" = "$want" ]; then
    continue
  fi
  tmpout="$(mktemp "$out_dir/.fivem-download.XXXXXX")"
  if ! curl --proto '=https' --proto-redir '=https' -sfL --retry 2 --max-time 1800 -A "$UA" -o "$tmpout" "$url"; then
    rm -f "$tmpout"
    echo "Download failed: $rel" >&2
    exit 1
  fi
  got="$(sha256sum "$tmpout" | cut -d' ' -f1)"
  if [ "$got" != "$want" ]; then
    rm -f "$tmpout"
    echo "SHA256 MISMATCH: $rel" >&2
    exit 1
  fi
  mv -f "$tmpout" "$out"
done

cp -f "$MAN" "$DEST/../manifest-$BUILD.json"
n="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["content_files"]))' "$MAN")"
echo "   $n files verified into $DEST"
