#!/usr/bin/env bash
# Fetch a Cfx depot product into the launcher's products/ tree, SHA256-verified.
#   fetch-product.sh <product> [branch]
# Layout mirrors what the launcher expects: products/<product>/<build>/<relative_path>
set -euo pipefail
. "$(dirname "$0")/env.sh"
PROD="${1:?usage: fetch-product.sh <product> [branch]}"
BRANCH="${2:-main}"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
LOCAL="$WINEPREFIX/drive_c/users/$WINE_USER/AppData/Local/FiveM for GTAV Enhanced"
MAN="$FIVEM_ROOT/dl/manifest-$PROD.json"

curl -sfL --max-time 60 -A "$UA" -o "$MAN" "https://depot.cfx.re/public/p/$PROD/u/$BRANCH"
BUILD="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["build"])' "$MAN")"
DEST="$LOCAL/products/$PROD/$BUILD"
mkdir -p "$DEST"
echo "== $PROD branch=$BRANCH build=$BUILD -> products/$PROD/$BUILD"

python3 -c '
import json,sys
m=json.load(open(sys.argv[1]))
for f in m["content_files"]:
    print("\t".join([f["download_url"], f["relative_path"], f["hash_sha256"]]))
' "$MAN" | while IFS=$'\t' read -r url rel want; do
  out="$DEST/$rel"; mkdir -p "$(dirname "$out")"
  if [ -f "$out" ] && [ "$(sha256sum "$out" | cut -d' ' -f1)" = "$want" ]; then continue; fi
  curl -sfL --max-time 1800 -A "$UA" -o "$out" "$url"
  got="$(sha256sum "$out" | cut -d' ' -f1)"
  [ "$got" = "$want" ] || { echo "  SHA256 MISMATCH: $rel" >&2; exit 1; }
done
cp -f "$MAN" "$DEST/../manifest-$BUILD.json" 2>/dev/null || true
n=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["content_files"]))' "$MAN")
echo "   $n files verified into $DEST"
