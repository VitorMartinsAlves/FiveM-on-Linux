#!/usr/bin/env bash
# Turn the WebView2 remote debugging port on (1) or off (0).
# FiveM sets its own AdditionalBrowserArguments, so the env var is ignored;
# the Edge *policy* key is appended and does work.
set -euo pipefail
. "$(dirname "$0")/env.sh"
K='Software\Policies\Microsoft\Edge\WebView2\AdditionalBrowserArguments'
ARGS='--remote-debugging-port=9222 --remote-allow-origins=*'
"$WINESERVER" -k 2>/dev/null || true; sleep 1
for HIVE in HKCU HKLM; do for V in "FiveM.exe" "*"; do
  if [ "${1:-1}" = "0" ]; then "$WINE" reg delete "$HIVE\\$K" /v "$V" /f  >/dev/null 2>&1 || true
  else                          "$WINE" reg add    "$HIVE\\$K" /v "$V" /t REG_SZ /d "$ARGS" /f >/dev/null 2>&1; fi
done; done
"$WINESERVER" -w
echo "devtools $([ "${1:-1}" = "0" ] && echo disabled || echo "enabled on 127.0.0.1:9222")"
