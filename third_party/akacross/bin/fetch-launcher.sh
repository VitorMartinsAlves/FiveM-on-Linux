#!/usr/bin/env bash
# Fetch the Enhanced FiveM launcher from the public Cfx depot and verify SHA256.
set -euo pipefail
. "$(dirname "$0")/env.sh"

MANIFEST_URL="https://depot.cfx.re/public/p/cfxlauncher/u/main"
DEST="${1:-$WINEPREFIX/drive_c/FiveM Enhanced}"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64)"

mkdir -p "$DEST" "$FIVEM_ROOT/dl"
manifest_tmp="$(mktemp "$FIVEM_ROOT/dl/.launcher-manifest.XXXXXX")"
trap 'rm -f "$manifest_tmp"' EXIT
curl --proto '=https' --proto-redir '=https' -sfL --retry 2 --max-time 90 -A "$UA" -o "$manifest_tmp" "$MANIFEST_URL"
python3 - "$manifest_tmp" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
files = data.get("content_files") if isinstance(data, dict) else None
build = data.get("build") if isinstance(data, dict) else None
valid_build = (
    isinstance(build, int) and not isinstance(build, bool) and build > 0
) or (
    isinstance(build, str) and build.isdigit() and int(build) > 0
)
if not isinstance(files, list) or not files:
    raise SystemExit("Cfx launcher manifest has no content files")
if not valid_build:
    raise SystemExit("Cfx launcher manifest has an invalid build identifier")
PY
install -m 0644 "$manifest_tmp" "$FIVEM_ROOT/dl/launcher-manifest.json"
build="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["build"])' "$manifest_tmp")"
echo "depot build: $build -> $DEST"

python3 - "$manifest_tmp" <<'PY' | while IFS=$'\t' read -r url rel want size; do
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
    size = str(item.get("bytes_count", ""))
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
    if not size.isdigit() or int(size) <= 0:
        raise SystemExit(f"Rejected invalid file size for {rel!r}")
    print("\t".join((url, rel, want, size)))
PY
  out_dir="$DEST/$(dirname "$rel")"
  mkdir -p "$out_dir"
  out="$DEST/$rel"
  if [ -f "$out" ] && [ "$(sha256sum "$out" | cut -d' ' -f1)" = "$want" ]; then
    printf '  ok (cached)  %s\n' "$rel"
    continue
  fi

  tmpout="$(mktemp "$out_dir/.fivem-download.XXXXXX")"
  if ! curl --proto '=https' --proto-redir '=https' -sfL --retry 2 --max-time 900 -A "$UA" -o "$tmpout" "$url"; then
    rm -f "$tmpout"
    echo "Download failed: $rel" >&2
    exit 1
  fi
  got="$(sha256sum "$tmpout" | cut -d' ' -f1)"
  if [ "$got" != "$want" ]; then
    rm -f "$tmpout"
    echo "SHA256 MISMATCH for $rel" >&2
    echo "  want $want" >&2
    echo "  got  $got" >&2
    exit 1
  fi
  mv -f "$tmpout" "$out"
  printf '  verified     %s\n' "$rel"
done

echo "$build" > "$DEST/.depot-build"

# The launcher expects modify.exe; download the official installer atomically and
# verify that the payload is a Windows PE executable before retaining it.
INSTALLER="$FIVEM_ROOT/dl/FiveM_Installer.exe"
if [ ! -s "$INSTALLER" ] || [ "$(od -An -N2 -tx1 "$INSTALLER" | tr -d ' \n')" != "4d5a" ]; then
  installer_tmp="$(mktemp "$FIVEM_ROOT/dl/.fivem-installer.XXXXXX")"
  if ! curl --proto '=https' --proto-redir '=https' -sfL --retry 2 --max-time 900 -A "$UA" -o "$installer_tmp" \
      "https://depot.cfx.re/public/p/cfxinstaller/u/main/c/FiveM_Installer.exe"; then
    rm -f "$installer_tmp"
    echo "Could not download the official FiveM Enhanced installer required by modify.exe." >&2
    exit 1
  fi
  [ "$(od -An -N2 -tx1 "$installer_tmp" | tr -d ' \n')" = "4d5a" ] || {
    rm -f "$installer_tmp"
    echo "Cfx installer download is not a valid Windows PE executable." >&2
    exit 1
  }
  mv -f "$installer_tmp" "$INSTALLER"
fi
