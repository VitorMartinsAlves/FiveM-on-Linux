#!/usr/bin/env bash
# Fetch the FiveM-for-GTAV-Enhanced launcher straight from the public Cfx depot,
# exactly as FiveM_Installer.exe would, and verify every file's SHA256.
set -euo pipefail
. "$(dirname "$0")/env.sh"
MANIFEST_URL="https://depot.cfx.re/public/p/cfxlauncher/u/main"
DEST="${1:-$WINEPREFIX/drive_c/FiveM Enhanced}"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64)"

mkdir -p "$DEST"
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
curl -sfL --max-time 60 -A "$UA" -o "$tmp" "$MANIFEST_URL"
build="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["build"])' "$tmp")"
echo "depot build: $build  ->  $DEST"

python3 - "$tmp" <<'PY' | while IFS=$'\t' read -r url rel want size; do
import json,sys
m=json.load(open(sys.argv[1]))
for f in m["content_files"]:
    print("\t".join([f["download_url"], f["relative_path"], f["hash_sha256"], str(f["bytes_count"])]))
PY
  out="$DEST/$rel"
  mkdir -p "$(dirname "$out")"
  if [ -f "$out" ] && [ "$(sha256sum "$out" | cut -d' ' -f1)" = "$want" ]; then
    printf '  ok (cached)  %s\n' "$rel"; continue
  fi
  printf '  downloading  %-24s %s bytes\n' "$rel" "$size"
  curl -sfL --max-time 900 -A "$UA" -o "$out" "$url"
  got="$(sha256sum "$out" | cut -d' ' -f1)"
  if [ "$got" != "$want" ]; then
    echo "  SHA256 MISMATCH for $rel" >&2; echo "    want $want" >&2; echo "    got  $got" >&2
    exit 1
  fi
  printf '  verified     %s\n' "$rel"
done
echo "$build" > "$DEST/.depot-build"
