#!/usr/bin/env bash
# Adapted for an existing Lutris/Rockstar Launcher prefix from akacross/fivem-enhanced-linux (MIT).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/bin/env.sh"
step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

[ -d "$WINEPREFIX/drive_c" ] || { echo "Selected path is not an existing Wine/Lutris prefix: $WINEPREFIX" >&2; exit 1; }
[ -f "$WINEPREFIX/system.reg" ] || { echo "system.reg missing. Select the Wine prefix configured in Lutris." >&2; exit 1; }
[ -f "$GTA_ENHANCED_DIR/GTA5_Enhanced.exe" ] || { echo "GTA5_Enhanced.exe not found under: $GTA_ENHANCED_DIR" >&2; exit 1; }

mkdir -p "$FIVEM_ROOT/backups" "$FIVEM_ROOT/dl"
BACKUP="$FIVEM_ROOT/backups/lutris-prefix-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
for f in system.reg user.reg userdef.reg; do
  [ ! -f "$WINEPREFIX/$f" ] || cp -a "$WINEPREFIX/$f" "$BACKUP/$f"
done
echo "Prefix registry backup: $BACKUP"

step "1/7  Existing Lutris prefix"
echo "   prefix: $WINEPREFIX"
echo "   Wine:   $WINE"
echo "   game:   $GTA_ENHANCED_DIR"
echo "   profile: $WINE_USER"

step "2/7  WebView2 runtime"
WV2_EXE="$FIVEM_ROOT/dl/MicrosoftEdgeWebView2RuntimeInstallerX64.exe"
if ! find "$WINEPREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application" \
        -name msedgewebview2.exe -print -quit 2>/dev/null | grep -q .; then
  [ -f "$WV2_EXE" ] || curl -sfL --max-time 900 -A "Mozilla/5.0" -o "$WV2_EXE" \
      "https://go.microsoft.com/fwlink/p/?LinkId=2124701"
  "$WINE" "$WV2_EXE" /silent /install || true
  "$WINESERVER" -w
fi
WEBVIEW_DIR="$WINEPREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application"
VER="$(find "$WEBVIEW_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | grep -E '^[0-9]+(\.[0-9]+)+$' | sort -V | tail -1 || true)"
if [ -z "$VER" ]; then
  echo "WebView2 wasn't detected after installation. It may need troubleshooting." >&2
else
  echo "   WebView2 $VER"
  export WEBVIEW2_VERSION="$VER"
fi

step "3/7  WebView2 registration"
GUID='{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
"$WINESERVER" -k 2>/dev/null || true
sleep 1
for VIEW in 64 32; do
  for HIVE in HKLM HKCU; do
    "$WINE" reg add "$HIVE\\SOFTWARE\\Microsoft\\EdgeUpdate\\Clients\\$GUID" /v pv /t REG_SZ /d "${VER:-0.0.0.0}" /f /reg:$VIEW >/dev/null 2>&1 || true
    "$WINE" reg add "$HIVE\\SOFTWARE\\Microsoft\\EdgeUpdate\\Clients\\$GUID" /v name /t REG_SZ /d "Microsoft Edge WebView2 Runtime" /f /reg:$VIEW >/dev/null 2>&1 || true
    "$WINE" reg add "$HIVE\\SOFTWARE\\Microsoft\\EdgeUpdate\\Clients\\$GUID" /v location /t REG_SZ /d "C:\\Program Files (x86)\\Microsoft\\EdgeWebView\\Application" /f /reg:$VIEW >/dev/null 2>&1 || true
  done
done
"$WINESERVER" -w

step "4/7  DXVK + VKD3D-Proton from the selected Lutris runner"
SYS="$WINEPREFIX/drive_c/windows/system32"
DXVK_DIR=""
for candidate in \
  "$LUTRIS_RUNNER_DIR/files/lib/wine/dxvk/x86_64-windows" \
  "$LUTRIS_RUNNER_DIR/lib/wine/dxvk/x86_64-windows" \
  "$LUTRIS_RUNNER_DIR/lib64/wine/dxvk/x86_64-windows" \
  "$LUTRIS_RUNNER_DIR/lib/wine/x86_64-windows" \
  "$LUTRIS_RUNNER_DIR/lib64/wine/x86_64-windows"; do
  if [ -f "$candidate/d3d11.dll" ] && [ -f "$candidate/dxgi.dll" ]; then DXVK_DIR="$candidate"; break; fi
done
if [ -n "$DXVK_DIR" ]; then
  mkdir -p "$BACKUP/system32"
  for name in d3d11.dll d3d10core.dll dxgi.dll d3d9.dll d3d12.dll d3d12core.dll; do
    if [ -e "$SYS/$name" ] || [ -L "$SYS/$name" ]; then cp -L --preserve=mode,timestamps "$SYS/$name" "$BACKUP/system32/$name" 2>/dev/null || true; fi
  done
  cp -f "$DXVK_DIR/"{d3d11,d3d10core,dxgi,d3d9}.dll "$SYS/"
  VKD3D_DIR="$(dirname "$(dirname "$DXVK_DIR")")/vkd3d-proton/x86_64-windows"
  if [ -f "$VKD3D_DIR/d3d12.dll" ] && [ -f "$VKD3D_DIR/d3d12core.dll" ]; then
    cp -f "$VKD3D_DIR/"{d3d12,d3d12core}.dll "$SYS/"
  fi
  echo "   DXVK copied from $DXVK_DIR; original DLLs (when present) backed up under $BACKUP/system32"
else
  echo "   WARNING: no DXVK DLLs found in selected Lutris runner; launcher may render black." >&2
  echo "   Enable DXVK for that runner or choose a runner with bundled DXVK." >&2
fi

step "5/7  GTA V Enhanced mapped to R:"
mkdir -p "$WINEPREFIX/dosdevices"
ln -sfn "$GTA_ENHANCED_DIR" "$WINEPREFIX/dosdevices/r:"
echo "   R:\\ -> $GTA_ENHANCED_DIR"

step "6/7  FiveM launcher and product files (SHA256 verified)"
bash "$HERE/bin/fetch-launcher.sh"
bash "$HERE/bin/fetch-product.sh" cfxui_gen9
bash "$HERE/bin/fetch-product.sh" fivem_gen9

step "7/7  Registry and configuration for Rockstar Games Launcher"
bash "$HERE/bin/register.sh"
bash "$HERE/bin/enable-devtools.sh" 1
CFG="$WINEPREFIX/drive_c/users/$WINE_USER/AppData/Roaming/FiveM for GTAV Enhanced/config.toml"
mkdir -p "$(dirname "$CFG")"
cat > "$CFG" <<EOF
gamepath = "R:\\\\"
gamePlatform = "$FIVEM_GAME_PLATFORM"
ui_updateChannel = "production"
EOF
echo "   config: $CFG"
printf '\n\033[1mFiveM for GTA V Enhanced staged in the Lutris prefix.\033[0m\n'
echo "Launch it from FiveM on Linux. Prefix backup: $BACKUP"
