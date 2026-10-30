#!/usr/bin/env bash
# Host-side handler for cfx:// URLs (Cfx account-link callbacks, cfx://connect/<id>).
#
# The client registers cfx:// INSIDE the wine prefix as `FiveM.exe "%1"`, but the
# Linux desktop has no handler, so KDE shows "no application found". This bridges
# that: desktop -> here -> FiveM.exe inside the prefix.
set -uo pipefail
. "$(dirname "$0")/env.sh"
URL="${1:-}"
[ -n "$URL" ] || { echo "usage: cfx-url-handler.sh cfx://..." >&2; exit 2; }
mkdir -p "$FIVEM_ROOT/logs"
cd "$WINEPREFIX/drive_c/FiveM Enhanced"
WINEDEBUG=-all exec "$WINE" "$WINEPREFIX/drive_c/FiveM Enhanced/FiveM.exe" "$URL" \
  >> "$FIVEM_ROOT/logs/cfx-url.log" 2>&1
