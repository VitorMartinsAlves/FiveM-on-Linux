#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="$HOME/.local/share/fivem-linux"
BIN_DIR="$HOME/.local/bin"
APP_DIR="$HOME/.local/share/applications"
CONFIG_DIR="$HOME/.config/fivem-linux"
RUNTIME_ROOT="$INSTALL_DIR/runtime"
BACKUP_ROOT="$RUNTIME_ROOT/backups"

fail() { printf '\n[FiveM on Linux] ERRO: %s\n' "$*" >&2; exit 1; }

ask_yes_no() {
  local answer
  read -r -p "$1 [s/N] " answer
  [[ "$answer" =~ ^([sS]|[sS][iI][mM])$ ]]
}

read_first_line() {
  REPLY=""
  [[ -f "$1" ]] || return 0
  IFS= read -r REPLY < "$1" || true
}

remove_cfx_association() {
  local previous="__NONE__"
  if [[ -f "$CONFIG_DIR/cfx-handler.previous" ]]; then
    read_first_line "$CONFIG_DIR/cfx-handler.previous"
    previous="$REPLY"
    [[ -n "$previous" ]] || previous="__NONE__"
  fi

  python3 - "$HOME" <<'PY'
from pathlib import Path
import re
import sys

home = Path(sys.argv[1])
desktop = "fivem-enhanced-lutris-cfx.desktop"
files = [
    home / ".config/mimeapps.list",
    home / ".config/kde-mimeapps.list",
    home / ".local/share/applications/mimeapps.list",
    home / ".local/share/applications/kde-mimeapps.list",
]
key_re = re.compile(r"^(\s*x-scheme-handler/cfx\s*=\s*)(.*)$")
for path in files:
    if not path.is_file():
        continue
    try:
        original = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        continue
    output = []
    changed = False
    for line in original.splitlines():
        match = key_re.match(line)
        if not match:
            output.append(line)
            continue
        old_items = [v for v in match.group(2).split(";") if v]
        items = [v for v in old_items if v != desktop]
        if items:
            output.append(match.group(1) + ";".join(items) + ";")
        else:
            changed = True
            continue
        changed = changed or len(items) != len(old_items)
    if changed:
        path.write_text("\n".join(output).rstrip() + ("\n" if output else ""), encoding="utf-8")
PY

  if [[ "$previous" != "__NONE__" && "$previous" != "fivem-enhanced-lutris-cfx.desktop" ]] && command -v xdg-mime >/dev/null 2>&1; then
    xdg-mime default "$previous" "x-scheme-handler/cfx" >/dev/null 2>&1 || \
      printf '[FiveM on Linux] AVISO: não foi possível restaurar o handler cfx:// anterior (%s).\n' "$previous" >&2
  fi
}

cleanup_application() {
  remove_cfx_association
  rm -f \
    "$BIN_DIR/fivem-linux" "$BIN_DIR/fivem-linux-uninstall" \
    "$APP_DIR/fivem-linux.desktop" "$APP_DIR/fivem-linux-uninstall.desktop" \
    "$APP_DIR/fivem-enhanced-lutris.desktop" "$APP_DIR/fivem-enhanced-lutris-cfx.desktop"
  rm -f \
    "$INSTALL_DIR/app.py" "$INSTALL_DIR/README.md" "$INSTALL_DIR/LICENSE" \
    "$INSTALL_DIR/uninstall.sh" "$INSTALL_DIR/launch-lutris.sh" "$INSTALL_DIR/launch-cfx-url.sh"
  rm -rf "$INSTALL_DIR/third_party" "$CONFIG_DIR"
  rmdir "$APP_DIR" 2>/dev/null || true
  rmdir "$BIN_DIR" 2>/dev/null || true
  rmdir "$INSTALL_DIR" 2>/dev/null || true
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
  fi
}

get_saved_prefix() {
  python3 - "$CONFIG_DIR/lutris-settings.json" <<'PY'
import json
import sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        data = json.load(f)
    print(data.get("prefix", ""))
except (OSError, ValueError, TypeError):
    print("")
PY
}

safe_product_key() {
  local key="$1" part
  [[ -n "$key" && "$key" != /* && "$key" != *\\* ]] || return 1
  [[ "$key" != *$'\t'* && "$key" != *$'\n'* && "$key" != *$'\r'* ]] || return 1
  IFS='/' read -r -a parts <<< "$key"
  for part in "${parts[@]}"; do
    [[ -n "$part" && "$part" != "." && "$part" != ".." ]] || return 1
  done
}

restore_prefix() {
  local prefix="$1"
  [[ -d "$prefix/drive_c" && -f "$prefix/system.reg" ]] || fail "O prefixo informado não parece válido: $prefix"
  [[ -d "$BACKUP_ROOT" ]] || fail "Não encontrei os backups em $BACKUP_ROOT."

  local backup="" candidate recorded
  while IFS= read -r candidate; do
    [[ -d "$candidate" && -f "$candidate/prefix.path" ]] || continue
    read_first_line "$candidate/prefix.path"
    recorded="$REPLY"
    if [[ "$recorded" == "$prefix" ]]; then
      backup="$candidate"
      break
    fi
  done < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'lutris-prefix-*' -print | sort -r)

  [[ -n "$backup" ]] || fail "Não encontrei um backup identificado para este prefixo. Para evitar restaurar o prefixo errado, nenhum arquivo foi alterado."
  [[ -s "$backup/system.reg" ]] || fail "O backup selecionado não contém system.reg. Nenhuma alteração foi feita."

  read_first_line "$backup/wine.path"; local wine="$REPLY"
  read_first_line "$backup/wineserver.path"; local wineserver="$REPLY"
  read_first_line "$backup/wine-user"; local wine_user="$REPLY"
  read_first_line "$backup/game.path"; local game_path="$REPLY"
  [[ -x "$wineserver" ]] || fail "Não encontrei o wineserver usado pela preparação: $wineserver."
  [[ -x "$wine" ]] || fail "Não encontrei o executável Wine registrado no backup: $wine."
  [[ -n "$wine_user" ]] || wine_user="${USER:-user}"

  printf '\nBackup selecionado: %s\nPrefixo: %s\nWine: %s\n' "$backup" "$prefix" "$wine"
  printf 'O rollback encerra TODOS os processos Wine deste prefixo. Feche o GTA, o Rockstar Launcher e outros programas antes de continuar.\n'
  printf 'Os arquivos completos system.reg/user.reg/userdef.reg serão substituídos pelo snapshot; alterações de registro feitas depois do backup serão perdidas.\n'
  printf 'O GTA V e o Rockstar Games Launcher não serão apagados.\n'
  ask_yes_no "Confirma o rollback deste prefixo?" || { echo "Rollback cancelado."; return 1; }

  export WINEPREFIX="$prefix"
  printf '\n[FiveM on Linux] Encerrando processos Wine deste prefixo...\n'
  "$wineserver" -k 2>/dev/null || true
  "$wineserver" -w

  printf '[FiveM on Linux] Restaurando os arquivos de registro...\n'
  local name
  for name in system.reg user.reg userdef.reg; do
    if [[ -f "$backup/$name" ]]; then
      cp -a "$backup/$name" "$prefix/$name"
    elif [[ -f "$backup/$name.absent" ]]; then
      rm -f "$prefix/$name"
    fi
  done

  printf '[FiveM on Linux] Restaurando DLLs do prefixo...\n'
  local sys="$prefix/drive_c/windows/system32"
  if [[ -d "$backup/system32" ]]; then
    mkdir -p "$sys"
    while IFS= read -r -d '' source_file; do
      rm -f -- "$sys/$(basename "$source_file")"
      cp -a "$source_file" "$sys/$(basename "$source_file")"
    done < <(find "$backup/system32" -mindepth 1 -maxdepth 1 -print0)
  fi
  if [[ -f "$backup/system32-created.txt" ]]; then
    while IFS= read -r name; do
      [[ "$name" =~ ^[A-Za-z0-9_.-]+$ ]] || continue
      rm -f -- "$sys/$name"
    done < "$backup/system32-created.txt"
  fi

  printf '[FiveM on Linux] Restaurando o mapeamento R:...\n'
  local drive="$prefix/dosdevices/r:" current_target="" expected_target=""
  [[ ! -L "$drive" ]] || current_target="$(readlink -f "$drive" 2>/dev/null || true)"
  if [[ -n "$game_path" ]]; then
    expected_target="$(readlink -f "$game_path" 2>/dev/null || printf '%s' "$game_path")"
  fi
  if [[ -L "$backup/dosdevices/r:" ]]; then
    if [[ ! -e "$drive" && ! -L "$drive" ]]; then
      mkdir -p "$prefix/dosdevices"
      cp -a "$backup/dosdevices/r:" "$drive"
    elif [[ -L "$drive" && -n "$expected_target" && "$current_target" == "$expected_target" ]]; then
      rm -f "$drive"
      cp -a "$backup/dosdevices/r:" "$drive"
    else
      printf '[FiveM on Linux] AVISO: R: foi alterado depois da instalação; mantive o mapeamento atual.\n' >&2
    fi
  elif [[ -f "$backup/r-drive-was-absent" ]]; then
    if [[ -L "$drive" && -n "$expected_target" && "$current_target" == "$expected_target" ]]; then
      rm -f "$drive"
    fi
  fi

  printf '[FiveM on Linux] Restaurando a pasta do launcher FiveM...\n'
  local launcher_dir="$prefix/drive_c/FiveM Enhanced"
  if [[ -e "$backup/FiveM Enhanced" || -L "$backup/FiveM Enhanced" ]]; then
    rm -rf "$launcher_dir"
    cp -a "$backup/FiveM Enhanced" "$launcher_dir"
  elif [[ -f "$backup/fivem-launcher-was-absent" ]]; then
    rm -rf "$launcher_dir"
  fi

  printf '[FiveM on Linux] Restaurando configuração do FiveM...\n'
  local config_file="$prefix/drive_c/users/$wine_user/AppData/Roaming/FiveM for GTAV Enhanced/config.toml"
  if [[ -f "$backup/config.toml" ]]; then
    mkdir -p "$(dirname "$config_file")"
    cp -a "$backup/config.toml" "$config_file"
  elif [[ -f "$backup/config-was-absent" ]]; then
    rm -f "$config_file"
  fi

  local product_root="$prefix/drive_c/users/$wine_user/AppData/Local/FiveM for GTAV Enhanced/products"
  printf '[FiveM on Linux] Restaurando arquivos de produtos e cache...\n'
  if [[ -f "$backup/product-files-overwritten.txt" ]]; then
    local key source_file target
    while IFS= read -r key; do
      safe_product_key "$key" || { printf '[FiveM on Linux] AVISO: caminho de backup inválido ignorado: %s\n' "$key" >&2; continue; }
      source_file="$backup/products-overwritten/$key"
      target="$product_root/$key"
      if [[ -e "$source_file" || -L "$source_file" ]]; then
        mkdir -p "$(dirname "$target")"
        rm -f -- "$target"
        cp -a "$source_file" "$target"
      fi
    done < "$backup/product-files-overwritten.txt"
  fi
  if [[ -f "$backup/product-files-created.txt" ]]; then
    local key target
    while IFS= read -r key; do
      safe_product_key "$key" || { printf '[FiveM on Linux] AVISO: caminho gerado inválido ignorado: %s\n' "$key" >&2; continue; }
      target="$product_root/$key"
      [[ ! -f "$target" && ! -L "$target" ]] || rm -f -- "$target"
    done < "$backup/product-files-created.txt"
  fi
  if [[ -f "$backup/product-builds-created.txt" ]]; then
    local key
    while IFS= read -r key; do
      safe_product_key "$key" || continue
      rmdir "$product_root/$key" 2>/dev/null || true
    done < "$backup/product-builds-created.txt"
  fi

  # WebView2 remains installed: Rockstar Games Launcher may share its runtime.
  rm -rf "$RUNTIME_ROOT/dl" "$RUNTIME_ROOT/logs" "$RUNTIME_ROOT/bin"
  printf '\n[FiveM on Linux] Rollback concluído. O backup foi preservado em:\n%s\n' "$backup"
}

usage() {
  cat <<'EOF'
Uso:
  uninstall.sh              Abre o menu interativo
  uninstall.sh --app-only   Remove apenas o aplicativo; não altera o prefixo Lutris
  uninstall.sh --rollback   Restaura o último backup do prefixo e remove o aplicativo

O diretório de backups é mantido mesmo após o rollback.
EOF
}

mode="${1:-}"
case "$mode" in
  --help|-h) usage; exit 0 ;;
  --app-only|--rollback|"") ;;
  *) usage; fail "Opção desconhecida: $mode" ;;
esac

if [[ -z "$mode" ]]; then
  printf 'FiveM on Linux — desinstalador\n\n'
  printf '1) Remover apenas o aplicativo (mantém as alterações no prefixo e os backups)\n'
  printf '2) Fazer rollback do prefixo Lutris e remover o aplicativo\n'
  printf '3) Cancelar\n\n'
  read -r -p "Escolha uma opção [1-3]: " choice
  case "$choice" in
    1) mode="--app-only" ;;
    2) mode="--rollback" ;;
    *) echo "Operação cancelada."; exit 0 ;;
  esac
fi

if [[ "$mode" == "--rollback" ]]; then
  prefix="$(get_saved_prefix)"
  read -r -p "Prefixo Lutris [$prefix]: " entered
  [[ -z "$entered" ]] || prefix="$entered"
  [[ -n "$prefix" ]] || fail "Não encontrei o prefixo salvo. Informe o caminho manualmente."
  prefix="$(realpath -m "$prefix")"
  restore_prefix "$prefix"
fi

if [[ "$mode" == "--app-only" || "$mode" == "--rollback" ]]; then
  printf '\n[FiveM on Linux] Removendo o aplicativo, atalhos e configurações locais...\n'
  cleanup_application
  printf '\nDesinstalação do aplicativo concluída.\n'
  printf 'Backups preservados em: %s\n' "$BACKUP_ROOT"
  if [[ "$mode" == "--app-only" ]]; then
    printf 'Atenção: nenhuma alteração foi desfeita dentro do prefixo Lutris.\n'
  fi
fi
