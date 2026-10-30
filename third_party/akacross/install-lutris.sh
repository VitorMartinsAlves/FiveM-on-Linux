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
  [ -s "$WV2_EXE" ] || curl -sfL --retry 2 --max-time 900 -A "Mozilla/5.0" -o "$WV2_EXE" \
      "https://go.microsoft.com/fwlink/p/?LinkId=2124701"
  "$WINE" "$WV2_EXE" /silent /install || {
    echo "WebView2 installer returned a non-zero exit code; checking whether it nevertheless installed." >&2
  }
  "$WINESERVER" -w
fi
WEBVIEW_DIR="$WINEPREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application"
VER="$(find "$WEBVIEW_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | grep -E '^[0-9]+(\.[0-9]+)+

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
mkdir -p "$SYS" "$FIVEM_ROOT/bin"
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
  for name in d3d11.dll d3d10core.dll dxgi.dll d3d9.dll d3d12.dll d3d12core.dll; do
    if [ -e "$SYS/$name" ] || [ -L "$SYS/$name" ]; then
      cp -L --preserve=mode,timestamps "$SYS/$name" "$BACKUP/system32/$name" 2>/dev/null || true
    fi
  done

  # D3D11 and DXGI are required for this path; the other DXVK DLLs are optional.
  for name in d3d11 dxgi d3d10core d3d9; do
    [ ! -f "$DXVK_DIR/$name.dll" ] || cp -f "$DXVK_DIR/$name.dll" "$SYS/$name.dll"
  done
  [ -s "$SYS/d3d11.dll" ] && [ -s "$SYS/dxgi.dll" ] || {
    echo "DXVK source was found but its required D3D11/DXGI files could not be copied." >&2
    exit 1
  }
  printf '%s\n' "$DXVK_DIR" > "$FIVEM_ROOT/bin/dxvk.active"

  VKD3D_DIR="$(dirname "$(dirname "$DXVK_DIR")")/vkd3d-proton/x86_64-windows"
  if [ -f "$VKD3D_DIR/d3d12.dll" ] && [ -f "$VKD3D_DIR/d3d12core.dll" ]; then
    cp -f "$VKD3D_DIR/d3d12.dll" "$SYS/d3d12.dll"
    cp -f "$VKD3D_DIR/d3d12core.dll" "$SYS/d3d12core.dll"
    printf '%s\n' "$VKD3D_DIR" > "$FIVEM_ROOT/bin/vkd3d.active"
  else
    rm -f "$FIVEM_ROOT/bin/vkd3d.active"
  fi
  echo "   DXVK copied from $DXVK_DIR"
else
  rm -f "$FIVEM_ROOT/bin/dxvk.active" "$FIVEM_ROOT/bin/vkd3d.active"
  echo "   WARNING: DXVK DLLs were not found in the selected Lutris runner." >&2
  echo "   Wine's built-in D3D renderer will be used; FiveM's UI may render black." >&2
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
if [ -f "$CFG" ]; then
  cp -a "$CFG" "$CFG.backup-$(date +%Y%m%d-%H%M%S)"
fi
python3 - "$CFG" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""
lines = text.splitlines()
section = re.compile(r"^\s*\[gta5enhanced\]\s*(?:#.*)?$")
section_start = next((i for i, line in enumerate(lines) if section.match(line)), None)
gamepath = 'gamepath = "R:/"'

if section_start is None:
    if lines and lines[-1].strip():
        lines.append("")
    lines.extend(["[gta5enhanced]", gamepath])
else:
    section_end = next(
        (i for i in range(section_start + 1, len(lines)) if re.match(r"^\s*\[[^\]]+\]", lines[i])),
        len(lines),
    )
    key_lines = [i for i in range(section_start + 1, section_end) if re.match(r"^\s*gamepath\s*=", lines[i])]
    if key_lines:
        lines[key_lines[0]] = gamepath
        for i in reversed(key_lines[1:]):
            del lines[i]
    else:
        lines.insert(section_start + 1, gamepath)

path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
PY
echo "   config: $CFG (gta5enhanced.gamepath = R:/)"
printf '\n\033[1mFiveM for GTA V Enhanced staged in the Lutris prefix.\033[0m\n'
echo "Launch it from FiveM on Linux. Prefix backup: $BACKUP"
 | sort -V | tail -1 || true)"
if [ -z "$VER" ] || ! find "$WEBVIEW_DIR/$VER" -name msedgewebview2.exe -print -quit 2>/dev/null | grep -q .; then
  echo "WebView2 was not installed or could not be located. Aborting instead of writing fake registry data." >&2
  exit 1
fi
echo "   WebView2 $VER"
export WEBVIEW2_VERSION="$VER"

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
mkdir -p "$SYS" "$FIVEM_ROOT/bin"
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
  for name in d3d11.dll d3d10core.dll dxgi.dll d3d9.dll d3d12.dll d3d12core.dll; do
    if [ -e "$SYS/$name" ] || [ -L "$SYS/$name" ]; then
      cp -L --preserve=mode,timestamps "$SYS/$name" "$BACKUP/system32/$name" 2>/dev/null || true
    fi
  done

  # D3D11 and DXGI are required for this path; the other DXVK DLLs are optional.
  for name in d3d11 dxgi d3d10core d3d9; do
    [ ! -f "$DXVK_DIR/$name.dll" ] || cp -f "$DXVK_DIR/$name.dll" "$SYS/$name.dll"
  done
  [ -s "$SYS/d3d11.dll" ] && [ -s "$SYS/dxgi.dll" ] || {
    echo "DXVK source was found but its required D3D11/DXGI files could not be copied." >&2
    exit 1
  }
  printf '%s\n' "$DXVK_DIR" > "$FIVEM_ROOT/bin/dxvk.active"

  VKD3D_DIR="$(dirname "$(dirname "$DXVK_DIR")")/vkd3d-proton/x86_64-windows"
  if [ -f "$VKD3D_DIR/d3d12.dll" ] && [ -f "$VKD3D_DIR/d3d12core.dll" ]; then
    cp -f "$VKD3D_DIR/d3d12.dll" "$SYS/d3d12.dll"
    cp -f "$VKD3D_DIR/d3d12core.dll" "$SYS/d3d12core.dll"
    printf '%s\n' "$VKD3D_DIR" > "$FIVEM_ROOT/bin/vkd3d.active"
  else
    rm -f "$FIVEM_ROOT/bin/vkd3d.active"
  fi
  echo "   DXVK copied from $DXVK_DIR"
else
  rm -f "$FIVEM_ROOT/bin/dxvk.active" "$FIVEM_ROOT/bin/vkd3d.active"
  echo "   WARNING: DXVK DLLs were not found in the selected Lutris runner." >&2
  echo "   Wine's built-in D3D renderer will be used; FiveM's UI may render black." >&2
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
