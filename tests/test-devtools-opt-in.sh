#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALLER="$ROOT/third_party/akacross/install-lutris.sh"
README="$ROOT/README.md"

# Normal prefix preparation must not expose the WebView2 debugging endpoint.
if grep -Fq 'bash "$HERE/bin/enable-devtools.sh" 1' "$INSTALLER"; then
  echo "Installer must not enable WebView2 DevTools by default." >&2
  exit 1
fi
grep -Fq 'bash "$HERE/bin/enable-devtools.sh" 0' "$INSTALLER"

grep -Fq 'DevTools do WebView2 (somente diagnóstico)' "$README"
grep -Fq 'enable-devtools.sh" 1' "$README"
grep -Fq 'enable-devtools.sh" 0' "$README"

echo "WebView2 DevTools remain opt-in."
