#!/usr/bin/env bash
# Do the bookkeeping FiveM_Installer.exe would have done:
#   - drop modify.exe (the installer copies itself under that name; it is the updater/uninstaller)
#   - save depot-manifest.json next to the launcher
#   - write the registry entries FiveM.exe reads to decide it is "installed"
set -euo pipefail
. "$(dirname "$0")/env.sh"
DEST="${1:-$WINEPREFIX/drive_c/FiveM Enhanced}"
WIN_DEST='C:\FiveM Enhanced'
LOCALAPP="C:\\users\\$WINE_USER\\AppData\\Local\\FiveM for GTAV Enhanced"
BUILD="$(cat "$DEST/.depot-build" 2>/dev/null || echo 138)"

cp -f "$FIVEM_ROOT/dl/FiveM_Installer.exe" "$DEST/modify.exe"
cp -f "$FIVEM_ROOT/dl/launcher-manifest.json" "$DEST/depot-manifest.json"
echo "placed modify.exe + depot-manifest.json in $DEST"

# Bump #4 defence: never write the registry while a wineserver is live.
"$WINESERVER" -k 2>/dev/null || true; sleep 1

r() { "$WINE" reg add "$1" /v "$2" /t REG_SZ /d "$3" /f >/dev/null 2>&1; }
for HIVE in HKCU HKLM; do
  r "$HIVE\\Software\\FiveM-for-GTAV-Enhanced" InstallLocation "$WIN_DEST"
  r "$HIVE\\Software\\FiveM-for-GTAV-Enhanced" DisplayVersion  "$BUILD"
  r "$HIVE\\Software\\FiveM-for-GTAV-Enhanced\\Settings" GameCacheLocation   "$LOCALAPP\\gamecache"
  r "$HIVE\\Software\\FiveM-for-GTAV-Enhanced\\Settings" ServerCacheLocation "$LOCALAPP\\servercache"
  U="$HIVE\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\FiveM-for-GTAV-Enhanced"
  r "$U" DisplayName     "FiveM for GTAV Enhanced"
  r "$U" DisplayVersion  "$BUILD"
  r "$U" DisplayIcon     "$WIN_DEST\\FiveM.exe"
  r "$U" InstallLocation "$WIN_DEST"
  r "$U" UninstallString "\"$WIN_DEST\\modify.exe\" --uninstall"
done
# Where GTA V Enhanced lives, so the launcher does not have to hunt for it.
r "HKLM\\SOFTWARE\\WOW6432Node\\Rockstar Games\\GTAV Enhanced" InstallFolder      "$GTA_DRIVE"
r "HKLM\\SOFTWARE\\WOW6432Node\\Rockstar Games\\GTAV Enhanced" InstallFolderSteam "$GTA_DRIVE"
r "HKLM\\SOFTWARE\\WOW6432Node\\Rockstar Games\\GTA V Enhanced" InstallFolder     "$GTA_DRIVE"
r "HKLM\\SOFTWARE\\WOW6432Node\\Rockstar Games\\GTA V Enhanced" InstallFolderSteam "$GTA_DRIVE"
mkdir -p "$WINEPREFIX/drive_c/users/$WINE_USER/AppData/Local/FiveM for GTAV Enhanced/"{gamecache,servercache}
"$WINESERVER" -w
echo "registry written."
