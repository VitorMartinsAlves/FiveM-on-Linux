#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
CONFIG_DIR="$HOME/.config/fivem-linux"
INSTALL_DIR="$HOME/.local/share/fivem-linux"
APP_DIR="$HOME/.local/share/applications"
BIN_DIR="$HOME/.local/bin"
RUNTIME="$INSTALL_DIR/runtime"
BACKUP="$RUNTIME/backups/lutris-prefix-test-001"
PREFIX="$TMP/lutris prefix"
GAME="$TMP/gta enhanced"
WINE="$TMP/runner/bin/wine"
WINESERVER="$TMP/runner/bin/wineserver"
WINE_USER="testuser"

mkdir -p \
  "$CONFIG_DIR" "$APP_DIR" "$BIN_DIR" "$BACKUP" \
  "$PREFIX/drive_c/windows/system32" "$PREFIX/dosdevices" \
  "$PREFIX/drive_c/users/$WINE_USER/AppData/Roaming/FiveM for GTAV Enhanced" \
  "$PREFIX/drive_c/users/$WINE_USER/AppData/Local/FiveM for GTAV Enhanced/products/cfxui_gen9/100" \
  "$PREFIX/drive_c/users/$WINE_USER/AppData/Local/FiveM for GTAV Enhanced/products/fivem_gen9/200" \
  "$PREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application/123.4.5"
mkdir -p "$(dirname "$WINE")"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WINE"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$TMP/wineserver.log" > "$WINESERVER"
chmod +x "$WINE" "$WINESERVER"

echo "original registry" > "$BACKUP/system.reg"
echo "original user registry" > "$BACKUP/user.reg"
echo "modified registry" > "$PREFIX/system.reg"
echo "modified user registry" > "$PREFIX/user.reg"
printf '%s\n' "$PREFIX" > "$BACKUP/prefix.path"
printf '%s\n' "$WINE" > "$BACKUP/wine.path"
printf '%s\n' "$WINESERVER" > "$BACKUP/wineserver.path"
printf '%s\n' "$GAME" > "$BACKUP/game.path"
printf '%s\n' "$WINE_USER" > "$BACKUP/wine-user"

echo "original dxgi" > "$BACKUP/system32-dxgi.tmp"
mkdir -p "$BACKUP/system32"
mv "$BACKUP/system32-dxgi.tmp" "$BACKUP/system32/dxgi.dll"
echo "modified dxgi" > "$PREFIX/drive_c/windows/system32/dxgi.dll"
echo "new d3d11" > "$PREFIX/drive_c/windows/system32/d3d11.dll"
printf 'd3d11.dll\n' > "$BACKUP/system32-created.txt"

mkdir -p "$TMP/old R drive" "$GAME" "$BACKUP/dosdevices"
ln -s "$TMP/old R drive" "$BACKUP/dosdevices/r:"
ln -s "$GAME" "$PREFIX/dosdevices/r:"
mkdir -p "$BACKUP/FiveM Enhanced"
echo "old launcher" > "$BACKUP/FiveM Enhanced/old-launcher.dat"
mkdir -p "$PREFIX/drive_c/FiveM Enhanced"
echo "new launcher" > "$PREFIX/drive_c/FiveM Enhanced/new-launcher.dat"

CONFIG_FILE="$PREFIX/drive_c/users/$WINE_USER/AppData/Roaming/FiveM for GTAV Enhanced/config.toml"
echo "original config" > "$BACKUP/config.toml"
echo "modified config" > "$CONFIG_FILE"

PRODUCT_ROOT="$PREFIX/drive_c/users/$WINE_USER/AppData/Local/FiveM for GTAV Enhanced/products"
echo "new product file" > "$PRODUCT_ROOT/cfxui_gen9/100/new.dat"
echo "modified old file" > "$PRODUCT_ROOT/fivem_gen9/200/existing.dat"
mkdir -p "$BACKUP/products-overwritten/fivem_gen9/200"
echo "original old file" > "$BACKUP/products-overwritten/fivem_gen9/200/existing.dat"
printf 'fivem_gen9/200/existing.dat\n' > "$BACKUP/product-files-overwritten.txt"
printf 'cfxui_gen9/100/new.dat\n' > "$BACKUP/product-files-created.txt"
printf 'cfxui_gen9/100\n' > "$BACKUP/product-builds-created.txt"

echo "shared webview runtime" > "$PREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application/123.4.5/msedgewebview2.exe"
mkdir -p "$RUNTIME/dl" "$RUNTIME/logs" "$RUNTIME/bin" "$INSTALL_DIR/third_party/akacross"
echo "test app" > "$INSTALL_DIR/app.py"
echo "test menu" > "$APP_DIR/fivem-linux.desktop"
echo "test cfx" > "$APP_DIR/fivem-enhanced-lutris-cfx.desktop"
echo "test cli" > "$BIN_DIR/fivem-linux"
echo "test uninstall cli" > "$BIN_DIR/fivem-linux-uninstall"
printf '__NONE__\n' > "$CONFIG_DIR/cfx-handler.previous"
mkdir -p "$HOME/.config"
printf '[Default Applications]\nx-scheme-handler/cfx=fivem-enhanced-lutris-cfx.desktop;org.kde.dolphin.desktop;\n' > "$HOME/.config/mimeapps.list"

python3 - "$CONFIG_DIR/lutris-settings.json" "$PREFIX" <<'PY'
import json
import sys
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump({"prefix": sys.argv[2]}, f)
PY

printf '\n\ny\n' | HOME="$HOME" bash "$ROOT/uninstall.sh" --rollback > "$TMP/uninstall.log" 2>&1 || {
  cat "$TMP/uninstall.log" >&2
  exit 1
}

grep -q "original registry" "$PREFIX/system.reg"
grep -q "original user registry" "$PREFIX/user.reg"
grep -q "original dxgi" "$PREFIX/drive_c/windows/system32/dxgi.dll"
[[ ! -e "$PREFIX/drive_c/windows/system32/d3d11.dll" ]]
[[ "$(readlink "$PREFIX/dosdevices/r:")" == "$TMP/old R drive" ]]
grep -q "old launcher" "$PREFIX/drive_c/FiveM Enhanced/old-launcher.dat"
[[ ! -e "$PREFIX/drive_c/FiveM Enhanced/new-launcher.dat" ]]
grep -q "original config" "$CONFIG_FILE"
grep -q "original old file" "$PRODUCT_ROOT/fivem_gen9/200/existing.dat"
[[ ! -e "$PRODUCT_ROOT/cfxui_gen9/100/new.dat" ]]
[[ -f "$PREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application/123.4.5/msedgewebview2.exe" ]]
[[ -d "$BACKUP" ]]
[[ ! -e "$INSTALL_DIR/app.py" ]]
[[ ! -e "$APP_DIR/fivem-linux.desktop" ]]
grep -q "org.kde.dolphin.desktop" "$HOME/.config/mimeapps.list"
grep -q -- "-k" "$TMP/wineserver.log"
grep -q -- "-w" "$TMP/wineserver.log"

printf 'uninstall rollback test passed\n'
