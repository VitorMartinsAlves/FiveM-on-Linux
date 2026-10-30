#!/usr/bin/env bash
# Diagnostic host-side handler for cfx:// URLs.
#
# Current Wine cannot reliably forward these URLs to the running FiveM process:
# the client probes \\\\.\\pipe\\ and Wine returns ERROR_NOT_SUPPORTED (50).
# A cold start with the URI also does not complete the callback. Do not spawn a
# second FiveM.exe instance or imply that authentication/join-link forwarding works.
set -euo pipefail
. "$(dirname "$0")/env.sh"

URL="${1:-}"
[ -n "$URL" ] || { echo "usage: cfx-url-handler.sh cfx://..." >&2; exit 2; }

mkdir -p "$FIVEM_ROOT/logs"
LOG="$FIVEM_ROOT/logs/cfx-url.log"

case "$URL" in
  cfx://auth/*)
    KIND="callback de autenticação"
    ;;
  cfx://connect/*)
    KIND="link de conexão"
    ;;
  *)
    KIND="link Cfx"
    ;;
esac

# Never write the full URI: auth links may contain short-lived credentials.
MESSAGE="Recebido $KIND, mas o FiveM Enhanced não consegue processar o redirecionamento no Wine. O Wine não oferece a enumeração de named pipes usada pelo cliente (erro 50). Nenhuma segunda instância foi iniciada."
printf '[%s] %s (URI omitida por segurança)\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$MESSAGE" >> "$LOG"

if command -v notify-send >/dev/null 2>&1; then
  notify-send --app-name="FiveM on Linux" --urgency=normal "Link Cfx não processado" "$MESSAGE" || true
fi

echo "$MESSAGE" >&2
echo "Log: $LOG" >&2
exit 78
