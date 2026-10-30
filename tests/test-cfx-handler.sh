#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PREFIX="$TMP/prefix"
RUNNER="$TMP/runner/bin"
GAME="$TMP/game"
HOME_DIR="$TMP/home"
RUNTIME="$TMP/runtime"
mkdir -p "$PREFIX/drive_c" "$RUNNER" "$GAME" "$HOME_DIR" "$TMP/fake-bin"

WINE="$RUNNER/wine"
WINESERVER="$RUNNER/wineserver"
cat > "$WINE" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/wine-invocations.log"
SH
cat > "$WINESERVER" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "$TMP/fake-bin/notify-send" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/notifications.log"
SH
chmod +x "$WINE" "$WINESERVER" "$TMP/fake-bin/notify-send"

OUTPUT="$(
  HOME="$HOME_DIR"   PATH="$TMP/fake-bin:$PATH"   WINEPREFIX="$PREFIX"   GTA_ENHANCED_DIR="$GAME"   WINE="$WINE"   WINESERVER="$WINESERVER"   FIVEM_ROOT="$RUNTIME"   bash "$ROOT/third_party/akacross/bin/cfx-url-handler.sh"     'cfx://auth/one-time-sensitive-payload' 2>&1
)"

grep -q "callback de autenticação" <<< "$OUTPUT"
grep -q "erro 50" <<< "$OUTPUT"
[[ "$OUTPUT" != *"one-time-sensitive-payload"* ]]
grep -q "callback de autenticação" "$RUNTIME/logs/cfx-url.log"
[[ "$(<"$RUNTIME/logs/cfx-url.log")" != *"one-time-sensitive-payload"* ]]
grep -q "callback de autenticação" "$HOME_DIR/notifications.log"
[[ "$(<"$HOME_DIR/notifications.log")" != *"one-time-sensitive-payload"* ]]
[[ ! -e "$HOME_DIR/wine-invocations.log" ]]

printf 'cfx URL handler redaction and no-duplicate-launch test passed\n'
