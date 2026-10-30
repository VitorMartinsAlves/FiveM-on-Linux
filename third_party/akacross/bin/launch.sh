#!/usr/bin/env bash
# Launch FiveM for GTAV Enhanced, then kick the updater (see kick-updater.py).
set -uo pipefail
. "$(dirname "$0")/env.sh"
mkdir -p "$FIVEM_ROOT/logs"
cd "$WINEPREFIX/drive_c/FiveM Enhanced"
# FIVEM_VDESKTOP=1 runs inside a Wine virtual desktop, which makes Wine draw its
# own software cursor - fallback if the Xcursor theme fix isn't enough.
if [ "${FIVEM_VDESKTOP:-0}" = "1" ]; then
  set -- explorer "/desktop=fivem,${FIVEM_VDESKTOP_SIZE:-1920x1080}" \
      "$WINEPREFIX/drive_c/FiveM Enhanced/FiveM.exe" "$@"
else
  set -- "$WINEPREFIX/drive_c/FiveM Enhanced/FiveM.exe" "$@"
fi
WINEDEBUG=-all setsid "$WINE" "$@" \
  >> "$FIVEM_ROOT/logs/launch-$(date +%Y%m%d).log" 2>&1 < /dev/null &
disown
python3 "$(dirname "$0")/kick-updater.py" || true
