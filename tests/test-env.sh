#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PREFIX="$TMP/prefix"
GAME="$TMP/game"
WINE="$TMP/runner/bin/wine"
WINESERVER="$TMP/runner/bin/wineserver"
RUNTIME="$TMP/runtime"
mkdir -p "$PREFIX/drive_c" "$GAME" "$(dirname "$WINE")"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WINE"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WINESERVER"
chmod +x "$WINE" "$WINESERVER"

# A fresh Lutris prefix has no WebView2 Application directory. Sourcing env.sh
# must not abort before install-lutris.sh gets a chance to install WebView2.
env -i \
  HOME="$TMP/home" USER=fixture PATH="$PATH" \
  WINEPREFIX="$PREFIX" GTA_ENHANCED_DIR="$GAME" \
  WINE="$WINE" WINESERVER="$WINESERVER" \
  FIVEM_ROOT="$RUNTIME" WINEDEBUG=-all \
  bash -c '
    set -euo pipefail
    source "$1"
    [[ -z "$WEBVIEW2_VERSION" ]]
    [[ "$WINEDLLOVERRIDES" == "wininet=builtin" ]]
  ' _ "$ROOT/third_party/akacross/bin/env.sh"

# When WebView2 is present, env.sh should select its newest version directory.
WEBVIEW_DIR="$PREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application"
mkdir -p "$WEBVIEW_DIR/123.4.5" "$WEBVIEW_DIR/99.9.9"
env -i \
  HOME="$TMP/home" USER=fixture PATH="$PATH" \
  WINEPREFIX="$PREFIX" GTA_ENHANCED_DIR="$GAME" \
  WINE="$WINE" WINESERVER="$WINESERVER" \
  FIVEM_ROOT="$RUNTIME" WINEDEBUG=-all \
  bash -c '
    set -euo pipefail
    source "$1"
    [[ "$WEBVIEW2_VERSION" == "123.4.5" ]]
    [[ "$WEBVIEW2_BROWSER_EXECUTABLE_FOLDER" == *"123.4.5" ]]
  ' _ "$ROOT/third_party/akacross/bin/env.sh"

printf 'env.sh missing/present WebView2 test passed\n'
