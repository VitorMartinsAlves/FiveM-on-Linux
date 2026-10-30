#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
CONFIG="$TMP/config.toml"

cat > "$CONFIG" <<'TOML'
# Keep this comment.
gamepath = "X:\\\\"
gamePlatform = "steam"
ui_updateChannel = "beta"
customRootValue = 7

[gta5enhanced]
gamepath = "wrong-old-format"
keepThis = "preserve"

[other]
value = "untouched"
TOML

python3 "$ROOT/third_party/akacross/bin/write-config.py" "$CONFIG"
python3 - "$CONFIG" <<'PY'
import sys
import tomllib
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
data = tomllib.loads(text)

assert data["gamepath"] == "R:\\\\", repr(data["gamepath"])
assert data["gamePlatform"] == "rockstar"
assert data["ui_updateChannel"] == "production"
assert data["customRootValue"] == 7
assert data["gta5enhanced"]["keepThis"] == "preserve"
assert "gamepath" not in data["gta5enhanced"]
assert data["other"]["value"] == "untouched"
assert text.count("gamepath =") == 1
assert text.count("gamePlatform =") == 1
assert text.count("ui_updateChannel =") == 1
PY

first="$(sha256sum "$CONFIG" | cut -d' ' -f1)"
python3 "$ROOT/third_party/akacross/bin/write-config.py" "$CONFIG"
second="$(sha256sum "$CONFIG" | cut -d' ' -f1)"
[[ "$first" == "$second" ]]

printf 'FiveM Enhanced config format and idempotency test passed\n'
