# Lutris/Wine integration — settings supplied by the GUI.
set -euo pipefail
export FIVEM_ROOT="${FIVEM_ROOT:-$HOME/.local/share/fivem-linux/runtime}"
: "${WINEPREFIX:?Select the existing Lutris prefix in the GUI first.}"
: "${GTA_ENHANCED_DIR:?Select the GTA V Enhanced folder in the GUI first.}"
export WINEARCH="${WINEARCH:-win64}"
export WINE="${WINE:-$(command -v wine || true)}"
[ -n "$WINE" ] && [ -x "$WINE" ] || { echo "Wine executable not found: $WINE" >&2; exit 1; }
export WINESERVER="${WINESERVER:-$(dirname "$WINE")/wineserver}"
[ -x "$WINESERVER" ] || WINESERVER="$(command -v wineserver || true)"
[ -n "$WINESERVER" ] && [ -x "$WINESERVER" ] || { echo "wineserver not found next to the selected Wine executable." >&2; exit 1; }
export PATH="$(dirname "$WINE"):$PATH"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-wininet=builtin;d3d9,d3d10core,d3d11,d3d12,d3d12core,dxgi=n}"
export WINEDEBUG="${WINEDEBUG:--all}"
export WINE_USER="${WINE_USER:-$USER}"
export FIVEM_GAME_PLATFORM="${FIVEM_GAME_PLATFORM:-rockstar}"
export LUTRIS_RUNNER_DIR="${LUTRIS_RUNNER_DIR:-$(dirname "$(dirname "$WINE")")}"
export GTA_DRIVE='R:\'
export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="--disable-gpu --no-sandbox --disable-gpu-compositing"
export XCURSOR_THEME="${XCURSOR_THEME:-breeze_cursors}"
export XCURSOR_SIZE="${XCURSOR_SIZE:-24}"
export WEBVIEW2_VERSION="${WEBVIEW2_VERSION:-}"
