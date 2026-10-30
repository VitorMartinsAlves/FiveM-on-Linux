#!/usr/bin/env bash
set -Eeuo pipefail

REPO="VitorMartinsAlves/FiveM-on-Linux"
BRANCH="main"
INSTALL_DIR="$HOME/.local/share/fivem-linux"
BIN_DIR="$HOME/.local/bin"
APP_DIR="$HOME/.local/share/applications"

fail() {
  printf '\n[FiveM on Linux] ERRO: %s\n' "$*" >&2
  exit 1
}

command -v curl >/dev/null 2>&1 || fail "curl não está instalado."
command -v tar >/dev/null 2>&1 || fail "tar não está instalado."
command -v python3 >/dev/null 2>&1 || {
  command -v sudo >/dev/null 2>&1 || fail "Python 3 não encontrado e sudo não está disponível."
  sudo pacman -S --needed python tk
}
if ! python3 -c 'import tkinter' >/dev/null 2>&1; then
  command -v pacman >/dev/null 2>&1 || fail "Tkinter não encontrado. Instale o pacote tk da sua distribuição."
  command -v sudo >/dev/null 2>&1 || fail "Tkinter não encontrado e sudo não está disponível."
  printf '[FiveM on Linux] Instalando a dependência gráfica Tkinter (pacote tk)...\n'
  sudo pacman -S --needed python tk
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
ARCHIVE="$TMP_DIR/project.tar.gz"
SOURCE_DIR="$TMP_DIR/source"
mkdir -p "$SOURCE_DIR"

printf '\n[FiveM on Linux] Baixando o projeto de GitHub...\n'
curl --proto '=https' --proto-redir '=https' -fL --retry 2 --connect-timeout 15 \
  "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" \
  -o "$ARCHIVE" || fail "Não foi possível baixar o projeto do GitHub."
tar -xzf "$ARCHIVE" --strip-components=1 -C "$SOURCE_DIR"

[[ -f "$SOURCE_DIR/app.py" ]] || fail "O arquivo app.py não foi encontrado no pacote baixado."
mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$APP_DIR"
install -m 0644 "$SOURCE_DIR/app.py" "$INSTALL_DIR/app.py"
[[ ! -f "$SOURCE_DIR/README.md" ]] || install -m 0644 "$SOURCE_DIR/README.md" "$INSTALL_DIR/README.md"
[[ ! -f "$SOURCE_DIR/LICENSE" ]] || install -m 0644 "$SOURCE_DIR/LICENSE" "$INSTALL_DIR/LICENSE"
if [[ -d "$SOURCE_DIR/third_party/akacross" ]]; then
  rm -rf "$INSTALL_DIR/third_party/akacross"
  mkdir -p "$INSTALL_DIR/third_party/akacross"
  cp -a "$SOURCE_DIR/third_party/akacross/." "$INSTALL_DIR/third_party/akacross/"
fi

cat > "$BIN_DIR/fivem-linux" <<EOF
#!/usr/bin/env bash
exec python3 "$INSTALL_DIR/app.py" "\$@"
EOF
chmod 0755 "$BIN_DIR/fivem-linux"

cat > "$APP_DIR/fivem-linux.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=FiveM on Linux
Comment=Preparar FiveM Enhanced usando Lutris e Rockstar Games Launcher
Exec=$BIN_DIR/fivem-linux
Icon=applications-games
Terminal=false
Categories=Game;Utility;
StartupNotify=true
EOF
chmod 0644 "$APP_DIR/fivem-linux.desktop"

printf '\n[FiveM on Linux] Instalação concluída.\n'
printf 'Comando para abrir depois: %s/fivem-linux\n' "$BIN_DIR"
printf 'Também foi criado um atalho no menu de aplicativos.\n\n'

rm -rf "$TMP_DIR"
trap - EXIT
exec python3 "$INSTALL_DIR/app.py"
