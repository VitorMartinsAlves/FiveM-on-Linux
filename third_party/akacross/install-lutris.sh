#!/usr/bin/env bash
# Adapted for an existing Lutris/Rockstar Launcher prefix from akacross/fivem-enhanced-linux (MIT).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/bin/env.sh"

step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

[ -d "$WINEPREFIX/drive_c" ] || fail "Selected path is not an existing Wine/Lutris prefix: $WINEPREFIX"
[ -f "$WINEPREFIX/system.reg" ] || fail "system.reg is missing. Select the Lutris prefix root."
[ -f "$GTA_ENHANCED_DIR/GTA5_Enhanced.exe" ] || fail "GTA5_Enhanced.exe was not found under: $GTA_ENHANCED_DIR"
[ -x "$WINE" ] || fail "Selected Wine executable is not executable: $WINE"
[ -x "$WINESERVER" ] || fail "Matching wineserver is missing: $WINESERVER"

mkdir -p "$FIVEM_ROOT/backups" "$FIVEM_ROOT/dl" "$FIVEM_ROOT/bin"
BACKUP="$FIVEM_ROOT/backups/lutris-prefix-$(date +%Y%m%d-%H%M%S)-$BASHPID"
mkdir -p "$BACKUP"
export FIVEM_BACKUP="$BACKUP"
printf '%s\n' "$WINEPREFIX" > "$BACKUP/prefix.path"
printf '%s\n' "$WINE" > "$BACKUP/wine.path"
printf '%s\n' "$WINESERVER" > "$BACKUP/wineserver.path"
printf '%s\n' "$GTA_ENHANCED_DIR" > "$BACKUP/game.path"
printf '%s\n' "$WINE_USER" > "$BACKUP/wine-user"
for f in system.reg user.reg userdef.reg; do
  if [ -f "$WINEPREFIX/$f" ]; then
    cp -a "$WINEPREFIX/$f" "$BACKUP/$f"
  else
    : > "$BACKUP/$f.absent"
  fi
done
echo "Prefix registry backup: $BACKUP"

step "1/7  Existing Lutris prefix"
echo "   prefix:  $WINEPREFIX"
echo "   Wine:    $WINE"
echo "   server:  $WINESERVER"
echo "   game:    $GTA_ENHANCED_DIR"
echo "   profile: $WINE_USER"
echo "   Ensure GTA V and Rockstar Games Launcher are fully closed before continuing."

step "2/7  WebView2 runtime"
WV2_EXE="$FIVEM_ROOT/dl/MicrosoftEdgeWebView2RuntimeInstallerX64.exe"
if ! find "$WINEPREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application" \
        -name msedgewebview2.exe -print -quit 2>/dev/null | grep -q .; then
  if [ ! -s "$WV2_EXE" ] || [ "$(od -An -N2 -tx1 "$WV2_EXE" | tr -d ' \n')" != "4d5a" ]; then
    wv2_tmp="$(mktemp "$FIVEM_ROOT/dl/.webview2-installer.XXXXXX")"
    if ! curl --proto '=https' --proto-redir '=https' -sfL --retry 2 --max-time 900 -A "Mozilla/5.0" -o "$wv2_tmp" \
        "https://go.microsoft.com/fwlink/p/?LinkId=2124701"; then
      rm -f "$wv2_tmp"
      fail "Could not download the Microsoft WebView2 offline installer."
    fi
    [ "$(od -An -N2 -tx1 "$wv2_tmp" | tr -d ' \n')" = "4d5a" ] || {
      rm -f "$wv2_tmp"
      fail "Downloaded WebView2 payload is not a Windows PE executable."
    }
    mv -f "$wv2_tmp" "$WV2_EXE"
  fi
  "$WINE" "$WV2_EXE" /silent /install || {
    echo "   WebView2 installer returned non-zero; checking the installed runtime." >&2
  }
  "$WINESERVER" -w
fi

WEBVIEW_DIR="$WINEPREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application"
VER="$(find "$WEBVIEW_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | \
  grep -E '^[0-9]+(\.[0-9]+)+$' | sort -V | tail -1 || true)"
if [ -z "$VER" ] || ! find "$WEBVIEW_DIR/$VER" -name msedgewebview2.exe -print -quit 2>/dev/null | grep -q .; then
  fail "WebView2 was not installed or could not be located. Aborting instead of writing false registry data."
fi
echo "   WebView2 $VER"
export WEBVIEW2_VERSION="$VER"

step "3/7  WebView2 registration"
GUID='{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
"$WINESERVER" -k 2>/dev/null || true
sleep 1
for VIEW in 64 32; do
  for HIVE in HKLM HKCU; do
    "$WINE" reg add "$HIVE\\SOFTWARE\\Microsoft\\EdgeUpdate\\Clients\\$GUID" /v pv /t REG_SZ /d "$VER" /f /reg:$VIEW >/dev/null 2>&1
    "$WINE" reg add "$HIVE\\SOFTWARE\\Microsoft\\EdgeUpdate\\Clients\\$GUID" /v name /t REG_SZ /d "Microsoft Edge WebView2 Runtime" /f /reg:$VIEW >/dev/null 2>&1
    "$WINE" reg add "$HIVE\\SOFTWARE\\Microsoft\\EdgeUpdate\\Clients\\$GUID" /v location /t REG_SZ /d "C:\\Program Files (x86)\\Microsoft\\EdgeWebView\\Application" /f /reg:$VIEW >/dev/null 2>&1
  done
done
"$WINESERVER" -w

step "4/7  DXVK + VKD3D-Proton from the selected Lutris runner"
SYS="$WINEPREFIX/drive_c/windows/system32"
mkdir -p "$SYS"
DXVK_DIR=""
for candidate in \
  "$LUTRIS_RUNNER_DIR/files/lib/wine/dxvk/x86_64-windows" \
  "$LUTRIS_RUNNER_DIR/lib/wine/dxvk/x86_64-windows" \
  "$LUTRIS_RUNNER_DIR/lib64/wine/dxvk/x86_64-windows" \
  "$LUTRIS_RUNNER_DIR/lib/wine/x86_64-windows" \
  "$LUTRIS_RUNNER_DIR/lib64/wine/x86_64-windows"; do
  if [ -f "$candidate/d3d11.dll" ] && [ -f "$candidate/dxgi.dll" ]; then
    DXVK_DIR="$candidate"
    break
  fi
done

if [ -n "$DXVK_DIR" ]; then
  mkdir -p "$BACKUP/system32"
  : > "$BACKUP/system32-created.txt"
  for name in d3d11.dll d3d10core.dll dxgi.dll d3d9.dll d3d12.dll d3d12core.dll; do
    if [ -e "$SYS/$name" ] || [ -L "$SYS/$name" ]; then
      cp -a "$SYS/$name" "$BACKUP/system32/$name"
    else
      printf '%s\n' "$name" >> "$BACKUP/system32-created.txt"
    fi
  done

  # Only D3D11 and DXGI are mandatory here; other DXVK DLLs vary by runner.
  for name in d3d11 dxgi d3d10core d3d9; do
    [ ! -f "$DXVK_DIR/$name.dll" ] || cp -f --remove-destination "$DXVK_DIR/$name.dll" "$SYS/$name.dll"
  done
  [ -s "$SYS/d3d11.dll" ] && [ -s "$SYS/dxgi.dll" ] || fail "DXVK D3D11/DXGI DLLs could not be copied."
  printf '%s\n' "$DXVK_DIR" > "$FIVEM_ROOT/bin/dxvk.active"

  VKD3D_DIR="$(dirname "$(dirname "$DXVK_DIR")")/vkd3d-proton/x86_64-windows"
  if [ -f "$VKD3D_DIR/d3d12.dll" ] && [ -f "$VKD3D_DIR/d3d12core.dll" ]; then
    cp -f --remove-destination "$VKD3D_DIR/d3d12.dll" "$SYS/d3d12.dll"
    cp -f --remove-destination "$VKD3D_DIR/d3d12core.dll" "$SYS/d3d12core.dll"
    printf '%s\n' "$VKD3D_DIR" > "$FIVEM_ROOT/bin/vkd3d.active"
  else
    rm -f "$FIVEM_ROOT/bin/vkd3d.active"
  fi
  echo "   DXVK copied from $DXVK_DIR"
else
  rm -f "$FIVEM_ROOT/bin/dxvk.active" "$FIVEM_ROOT/bin/vkd3d.active"
  echo "   WARNING: DXVK DLLs were not found in the selected Lutris runner." >&2
  echo "   Built-in Wine D3D rendering will be used; FiveM's UI may render black." >&2
fi

step "5/7  GTA V Enhanced mapped to R:"
DOSDEVICES="$WINEPREFIX/dosdevices"
R_DRIVE="$DOSDEVICES/r:"
mkdir -p "$DOSDEVICES"
if [ -e "$R_DRIVE" ] || [ -L "$R_DRIVE" ]; then
  if [ ! -L "$R_DRIVE" ]; then
    fail "The existing R: mapping is not a symlink. It was left untouched; move or back it up manually before continuing."
  fi
  mkdir -p "$BACKUP/dosdevices"
  cp -a "$R_DRIVE" "$BACKUP/dosdevices/r:"
  echo "   previous R: symlink backed up: $(readlink "$R_DRIVE")"
else
  : > "$BACKUP/r-drive-was-absent"
fi
ln -sfnT "$GTA_ENHANCED_DIR" "$R_DRIVE"
echo "   R:\\ -> $GTA_ENHANCED_DIR"

step "6/7  FiveM launcher and product files (SHA256 verified)"
LAUNCHER_DIR="$WINEPREFIX/drive_c/FiveM Enhanced"
if [ -e "$LAUNCHER_DIR" ] || [ -L "$LAUNCHER_DIR" ]; then
  cp -a "$LAUNCHER_DIR" "$BACKUP/FiveM Enhanced"
else
  : > "$BACKUP/fivem-launcher-was-absent"
fi
bash "$HERE/bin/fetch-launcher.sh"
bash "$HERE/bin/fetch-product.sh" cfxui_gen9
bash "$HERE/bin/fetch-product.sh" fivem_gen9

step "7/7  Registry and configuration for Rockstar Games Launcher"
bash "$HERE/bin/register.sh"
bash "$HERE/bin/enable-devtools.sh" 1

CFG="$WINEPREFIX/drive_c/users/$WINE_USER/AppData/Roaming/FiveM for GTAV Enhanced/config.toml"
mkdir -p "$(dirname "$CFG")"
if [ -L "$CFG" ]; then
  fail "The existing FiveM config.toml is a symbolic link. It was left untouched; move it aside before retrying."
elif [ -f "$CFG" ]; then
  cp -a "$CFG" "$BACKUP/config.toml"
else
  : > "$BACKUP/config-was-absent"
fi
python3 "$HERE/bin/write-config.py" "$CFG"
echo "   config: $CFG (gamepath, gamePlatform=rockstar, ui_updateChannel=production)"
printf '\n\033[1mFiveM for GTA V Enhanced staged in the Lutris prefix.\033[0m\n'
echo "Launch it from FiveM on Linux. Prefix backup: $BACKUP"
