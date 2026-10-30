# Lutris/Wine integration — settings supplied by the GUI.
set -euo pipefail
export FIVEM_ROOT="${FIVEM_ROOT:-$HOME/.local/share/fivem-linux/runtime}"
: "${WINEPREFIX:?Select the existing Lutris prefix in the GUI first.}"
: "${GTA_ENHANCED_DIR:?Select the GTA V Enhanced folder in the GUI first.}"
export WINEARCH="${WINEARCH:-win64}"
export WINE="${WINE:-$(command -v wine || true)}"
[ -n "$WINE" ] && [ -x "$WINE" ] || { echo "Wine executable not found: $WINE" >&2; exit 1; }

# Never mix a Lutris runner with a system wineserver from a different Wine build.
export WINESERVER="${WINESERVER:-$(dirname "$WINE")/wineserver}"
[ -x "$WINESERVER" ] || { echo "Matching wineserver not found next to selected Wine executable: $WINESERVER" >&2; exit 1; }

export PATH="$(dirname "$WINE"):$PATH"
export WINEDEBUG="${WINEDEBUG:--all}"
export WINE_USER="${WINE_USER:-$USER}"
export FIVEM_GAME_PLATFORM="${FIVEM_GAME_PLATFORM:-rockstar}"
export LUTRIS_RUNNER_DIR="${LUTRIS_RUNNER_DIR:-$(dirname "$(dirname "$WINE")")}"
export GTA_DRIVE='R:\'
export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="--disable-gpu --no-sandbox --disable-gpu-compositing"
export XCURSOR_THEME="${XCURSOR_THEME:-breeze_cursors}"
export XCURSOR_SIZE="${XCURSOR_SIZE:-24}"

if [ -z "${WEBVIEW2_VERSION:-}" ]; then
  WEBVIEW2_VERSION="$(find "$WINEPREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | grep -E '^[0-9]+(\.[0-9]+)+
fi
export WEBVIEW2_VERSION
if [ -s "$FIVEM_ROOT/bin/webview2.selected" ]; then
  export WEBVIEW2_BROWSER_EXECUTABLE_FOLDER="$(cat "$FIVEM_ROOT/bin/webview2.selected")"
elif [ -n "$WEBVIEW2_VERSION" ]; then
  export WEBVIEW2_BROWSER_EXECUTABLE_FOLDER="C:\\Program Files (x86)\\Microsoft\\EdgeWebView\\Application\\$WEBVIEW2_VERSION"
fi

# Enable native DXVK/VKD3D only when the installer copied those exact runtime DLLs.
SYS="$WINEPREFIX/drive_c/windows/system32"
OVERRIDES="${WINEDLLOVERRIDES:-wininet=builtin}"
if [ -s "$FIVEM_ROOT/bin/dxvk.active" ] && [ -s "$SYS/d3d11.dll" ] && [ -s "$SYS/dxgi.dll" ]; then
  OVERRIDES="${OVERRIDES};d3d11,dxgi=n"
  [ ! -s "$SYS/d3d10core.dll" ] || OVERRIDES="${OVERRIDES};d3d10core=n"
  [ ! -s "$SYS/d3d9.dll" ] || OVERRIDES="${OVERRIDES};d3d9=n"
fi
if [ -s "$FIVEM_ROOT/bin/vkd3d.active" ] && [ -s "$SYS/d3d12.dll" ] && [ -s "$SYS/d3d12core.dll" ]; then
  OVERRIDES="${OVERRIDES};d3d12,d3d12core=n"
fi
export WINEDLLOVERRIDES="$OVERRIDES"
 | sort -V | tail -1 || true)"
fi
export WEBVIEW2_VERSION
if [ -s "$FIVEM_ROOT/bin/webview2.selected" ]; then
  export WEBVIEW2_BROWSER_EXECUTABLE_FOLDER="$(cat "$FIVEM_ROOT/bin/webview2.selected")"
elif [ -n "$WEBVIEW2_VERSION" ]; then
  export WEBVIEW2_BROWSER_EXECUTABLE_FOLDER="C:\\Program Files (x86)\\Microsoft\\EdgeWebView\\Application\\$WEBVIEW2_VERSION"
fi

# Enable native DXVK/VKD3D only when the installer copied those exact runtime DLLs.
SYS="$WINEPREFIX/drive_c/windows/system32"
OVERRIDES="${WINEDLLOVERRIDES:-wininet=builtin}"
if [ -s "$FIVEM_ROOT/bin/dxvk.active" ] && [ -s "$SYS/d3d11.dll" ] && [ -s "$SYS/dxgi.dll" ]; then
  OVERRIDES="${OVERRIDES};d3d11,dxgi=n"
  [ ! -s "$SYS/d3d10core.dll" ] || OVERRIDES="${OVERRIDES};d3d10core=n"
  [ ! -s "$SYS/d3d9.dll" ] || OVERRIDES="${OVERRIDES};d3d9=n"
fi
if [ -s "$FIVEM_ROOT/bin/vkd3d.active" ] && [ -s "$SYS/d3d12.dll" ] && [ -s "$SYS/d3d12core.dll" ]; then
  OVERRIDES="${OVERRIDES};d3d12,d3d12core=n"
fi
export WINEDLLOVERRIDES="$OVERRIDES"
