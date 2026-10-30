#!/usr/bin/env python3
"""Visual setup for FiveM Enhanced using an existing Lutris/Rockstar Wine prefix."""

from __future__ import annotations

import json
import os
import queue
import re
import shlex
import shutil
import subprocess
import threading
import time
from pathlib import Path
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

HOME = Path.home()
APP_DIR = Path(__file__).resolve().parent
VENDOR_DIR = APP_DIR / "third_party" / "akacross"
INSTALL_SCRIPT = VENDOR_DIR / "install-lutris.sh"
VENDOR_BIN = VENDOR_DIR / "bin"
CONFIG_DIR = HOME / ".config" / "fivem-linux"
SETTINGS_FILE = CONFIG_DIR / "lutris-settings.json"
ENV_FILE = CONFIG_DIR / "lutris.env"
RUNTIME_ROOT = HOME / ".local" / "share" / "fivem-linux" / "runtime"
FIVEM_EXE_REL = Path("drive_c") / "FiveM Enhanced" / "FiveM.exe"
GAME_EXE = "GTA5_Enhanced.exe"

BG = "#0b0e14"
PANEL = "#141a24"
PANEL_2 = "#1b2432"
TEXT = "#edf2f7"
MUTED = "#9aa9bc"
ACCENT = "#fb923c"
GREEN = "#4ade80"
RED = "#fb7185"


def expand_path(value: str) -> Path:
    return Path(os.path.expandvars(value.strip().strip('"').strip("'"))).expanduser()


def is_prefix(path: Path) -> bool:
    return path.is_dir() and (path / "drive_c").is_dir() and (path / "system.reg").is_file()


def has_game(path: Path) -> bool:
    return (path / GAME_EXE).is_file()


def lutris_config_dirs() -> list[Path]:
    return [
        HOME / ".config/lutris/games",
        HOME / ".local/share/lutris/games",
        HOME / ".var/app/net.lutris.Lutris/config/lutris/games",
        HOME / ".var/app/net.lutris.Lutris/data/lutris/games",
    ]


def config_records() -> list[dict]:
    records = []
    seen = set()
    for directory in lutris_config_dirs():
        if not directory.is_dir():
            continue
        try:
            candidates = list(directory.glob("*.yml")) + list(directory.glob("*.yaml"))
        except OSError:
            continue
        for cfg in candidates:
            try:
                content = cfg.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            prefix_match = re.search(r"(?m)^\s*prefix:\s*(.+?)\s*$", content)
            exe_match = re.search(r"(?m)^\s*exe:\s*(.+?)\s*$", content)
            version_match = re.search(r"(?m)^\s*version:\s*(.+?)\s*$", content)
            prefix = expand_path(prefix_match.group(1)) if prefix_match else None
            exe = expand_path(exe_match.group(1)) if exe_match else None
            version = version_match.group(1).strip().strip('"').strip("'") if version_match else ""
            key = str(cfg)
            if key in seen:
                continue
            seen.add(key)
            records.append({
                "config": cfg,
                "name": cfg.stem.lower(),
                "text": content.lower(),
                "prefix": prefix if prefix and is_prefix(prefix) else None,
                "exe": exe,
                "version": version,
            })
    return records


def wine_candidates() -> list[Path]:
    results: list[Path] = []
    roots = [
        HOME / ".local/share/lutris/runners/wine",
        HOME / ".var/app/net.lutris.Lutris/data/lutris/runners/wine",
        HOME / ".var/app/net.lutris.Lutris/config/lutris/runners/wine",
    ]
    for root in roots:
        if root.is_dir():
            try:
                for candidate in root.glob("*/bin/wine"):
                    if candidate.is_file() and os.access(candidate, os.X_OK):
                        results.append(candidate.resolve())
            except OSError:
                pass
    system_wine = shutil.which("wine")
    if system_wine:
        results.append(Path(system_wine).resolve())
    unique = {str(p): p for p in results}
    ordered = sorted(unique.values(), key=lambda p: (0 if "lutris" in str(p).lower() or "proton" in str(p).lower() else 1, str(p)), reverse=False)
    return ordered


def runner_from_version(version: str) -> Path | None:
    if not version:
        return None
    for root in (
        HOME / ".local/share/lutris/runners/wine",
        HOME / ".var/app/net.lutris.Lutris/data/lutris/runners/wine",
        HOME / ".var/app/net.lutris.Lutris/config/lutris/runners/wine",
    ):
        candidate = root / version / "bin" / "wine"
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate.resolve()
    return None


def detect_defaults() -> tuple[Path | None, Path | None, Path | None]:
    records = config_records()
    prefixes = [r for r in records if r["prefix"]]
    preferred = [
        r for r in prefixes
        if any(word in r["name"] + " " + r["text"] for word in ("rockstar", "grand theft auto", "gta v", "gtav"))
    ]
    chosen = preferred[0] if preferred else (prefixes[0] if prefixes else None)
    prefix = chosen["prefix"] if chosen else None

    # Never pair a known prefix with an arbitrary Wine build. Lutris stores the
    # selected runner version in its game YAML; if it cannot be resolved, require
    # the user to choose the matching executable instead of guessing.
    wine = runner_from_version(chosen["version"]) if chosen and chosen["version"] else None
    if not chosen:
        candidates = wine_candidates()
        if len(candidates) == 1:
            wine = candidates[0]

    game_dir = None
    for record in records:
        exe = record["exe"]
        if exe and exe.name.lower() == GAME_EXE.lower() and has_game(exe.parent):
            game_dir = exe.parent.resolve()
            break
    return prefix, game_dir, wine


def profile_for_prefix(prefix: Path) -> str:
    users = prefix / "drive_c" / "users"
    explicit = os.environ.get("FIVEM_WINE_USER") or os.environ.get("WINE_USER")
    if explicit and (users / explicit / "AppData").is_dir():
        return explicit
    if users.is_dir():
        candidates = []
        try:
            for user_dir in users.iterdir():
                if not user_dir.is_dir() or user_dir.name.lower() in {"public", "all users", "default", "default user"}:
                    continue
                score = 0
                if (user_dir / "AppData/Local/Rockstar Games/Launcher").is_dir():
                    score += 10
                if (user_dir / "AppData/Roaming/Rockstar Games").is_dir():
                    score += 5
                if (user_dir / "AppData/Local").is_dir():
                    score += 1
                if user_dir.name.lower() == os.environ.get("USER", "").lower():
                    score += 2
                candidates.append((score, user_dir.name))
        except OSError:
            pass
        if candidates:
            candidates.sort(reverse=True)
            return candidates[0][1]
    return os.environ.get("USER", "user")


def runner_root(wine: Path) -> Path:
    return wine.parent.parent if wine.parent.name == "bin" else wine.parent


def wineserver_for(wine: Path) -> Path | None:
    # A wineserver from another Wine build can corrupt or terminate the selected prefix.
    adjacent = wine.resolve().parent / "wineserver"
    if adjacent.is_file() and os.access(adjacent, os.X_OK):
        return adjacent.resolve()
    return None


def is_proton_runner(wine: Path) -> bool:
    """Return True for Proton/GE-Proton executables that must be launched via UMU."""
    parts = [part.lower() for part in wine.parts]

    def is_proton_dir(name: str) -> bool:
        return name == "proton" or name.startswith((
            "proton-", "proton_", "proton ", "ge-proton", "lutris-ge-proton", "umu-proton"
        ))

    for index, part in enumerate(parts):
        if part == "compatibilitytools.d" and index + 1 < len(parts):
            return is_proton_dir(parts[index + 1])
        if part == "runners" and index + 2 < len(parts):
            # Lutris runners are stored under runners/<runner-type>/<runner-name>.
            if is_proton_dir(parts[index + 2]):
                return True
        if part == "common" and "steamapps" in parts[:index] and index + 1 < len(parts):
            if is_proton_dir(parts[index + 1]):
                return True
    return False


class FiveMLutrisApp:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.events: queue.Queue = queue.Queue()
        self.busy = False
        self.prefix_var = tk.StringVar()
        self.game_var = tk.StringVar()
        self.wine_var = tk.StringVar()
        self.path_buttons = []
        self.status_var = tk.StringVar(value="Detectando instalações do Lutris...")
        self.detail_var = tk.StringVar(value="GTA V Enhanced • Rockstar Games Launcher • Lutris/Wine")
        self.init_style()
        self.build_ui()
        self.load_settings_and_detect()
        self.refresh_status()
        self.root.protocol("WM_DELETE_WINDOW", self.on_close)
        self.root.after(120, self.poll_events)

    def init_style(self):
        self.root.title("FiveM on Linux — Lutris")
        self.root.geometry("970x790")
        self.root.minsize(840, 700)
        self.root.configure(bg=BG)
        style = ttk.Style(self.root)
        style.theme_use("clam")
        style.configure("TLabel", background=BG, foreground=TEXT, font=("Inter", 10))
        style.configure("Muted.TLabel", background=BG, foreground=MUTED, font=("Inter", 9))
        style.configure("Title.TLabel", background=BG, foreground=TEXT, font=("Inter", 23, "bold"))
        style.configure("Section.TLabel", background=PANEL, foreground=TEXT, font=("Inter", 11, "bold"))
        style.configure("TEntry", fieldbackground=PANEL_2, foreground=TEXT, bordercolor=PANEL_2, insertcolor=TEXT)
        style.configure("TProgressbar", troughcolor=PANEL_2, background=ACCENT, bordercolor=PANEL_2)

    def button(self, parent, text, command, primary=False):
        bg = ACCENT if primary else PANEL_2
        fg = "#111827" if primary else TEXT
        return tk.Button(
            parent, text=text, command=command, bg=bg, fg=fg,
            activebackground=ACCENT if primary else "#2a3546", activeforeground=fg,
            relief="flat", borderwidth=0, padx=12, pady=9, cursor="hand2",
            font=("Inter", 9, "bold"), disabledforeground="#6b7280"
        )

    def card(self, parent, title, value):
        frame = tk.Frame(parent, bg=PANEL, padx=14, pady=12, highlightthickness=1, highlightbackground="#222c3b")
        tk.Label(frame, text=title.upper(), bg=PANEL, fg=MUTED, font=("Inter", 8, "bold")).pack(anchor="w")
        label = tk.Label(frame, text=value, bg=PANEL, fg=TEXT, font=("Inter", 10, "bold"), wraplength=380, justify="left")
        label.pack(anchor="w", pady=(7, 0))
        return frame, label

    def build_ui(self):
        outer = tk.Frame(self.root, bg=BG, padx=22, pady=20)
        outer.pack(fill="both", expand=True)

        header = tk.Frame(outer, bg=BG)
        header.pack(fill="x")
        tk.Label(header, text="F", bg=ACCENT, fg="#111827", font=("Inter", 20, "bold"), width=2, height=1).pack(side="left", padx=(0, 12))
        titlebox = tk.Frame(header, bg=BG)
        titlebox.pack(side="left", fill="x", expand=True)
        ttk.Label(titlebox, text="FiveM on Linux", style="Title.TLabel").pack(anchor="w")
        ttk.Label(titlebox, text="LUTRIS + ROCKSTAR GAMES LAUNCHER", style="Muted.TLabel").pack(anchor="w", pady=(3, 0))
        self.refresh_btn = self.button(header, "ATUALIZAR", self.refresh_status)
        self.refresh_btn.pack(side="right")
        tk.Frame(outer, bg="#263144", height=1).pack(fill="x", pady=16)

        hero = tk.Frame(outer, bg=PANEL, padx=18, pady=15, highlightthickness=1, highlightbackground="#263144")
        hero.pack(fill="x")
        ttk.Label(hero, textvariable=self.status_var, style="Section.TLabel").pack(anchor="w")
        ttk.Label(hero, textvariable=self.detail_var, style="Muted.TLabel").pack(anchor="w", pady=(5, 0))
        self.progress = ttk.Progressbar(hero, mode="indeterminate")
        self.progress.pack(fill="x", pady=(13, 0))

        selector = tk.Frame(outer, bg=PANEL, padx=16, pady=14, highlightthickness=1, highlightbackground="#263144")
        selector.pack(fill="x", pady=(13, 0))
        self.prefix_entry = self.add_path_row(selector, "PREFIXO DO LUTRIS (pasta com system.reg e drive_c)", self.prefix_var, self.browse_prefix)
        self.game_entry = self.add_path_row(selector, "PASTA DO GTA V ENHANCED (contém GTA5_Enhanced.exe)", self.game_var, self.browse_game)
        self.wine_entry = self.add_path_row(selector, "EXECUTÁVEL WINE DO RUNNER LUTRIS", self.wine_var, self.browse_wine)

        cards = tk.Frame(outer, bg=BG)
        cards.pack(fill="x", pady=(13, 0))
        self.status_cards = {}
        for index, (name, val) in enumerate([
            ("Jogo", "Selecionar pasta"),
            ("Prefixo Lutris", "Selecionar prefixo"),
            ("Runner Wine", "Detectando"),
            ("FiveM Enhanced", "Ainda não preparado"),
        ]):
            frame, label = self.card(cards, name, val)
            frame.grid(row=index // 2, column=index % 2, sticky="nsew", padx=(0 if index % 2 == 0 else 7, 7 if index % 2 == 0 else 0), pady=4)
            cards.grid_columnconfigure(index % 2, weight=1)
            self.status_cards[name] = label

        actions = tk.Frame(outer, bg=BG)
        actions.pack(fill="x", pady=(12, 7))
        self.prepare_btn = self.button(actions, "PREPARAR NESTE PREFIXO", self.prepare, primary=True)
        self.prepare_btn.pack(side="left")
        self.launch_btn = self.button(actions, "ABRIR FIVEM", self.launch)
        self.launch_btn.pack(side="left", padx=(8, 0))
        self.open_prefix_btn = self.button(actions, "ABRIR PASTA DO PREFIXO", self.open_prefix)
        self.open_prefix_btn.pack(side="left", padx=(8, 0))

        lower = tk.Frame(outer, bg=BG)
        lower.pack(fill="both", expand=True, pady=(8, 0))
        notes = tk.Frame(lower, bg=PANEL, padx=14, pady=12)
        notes.pack(side="left", fill="both", expand=True, padx=(0, 7))
        tk.Label(notes, text="ANTES DE PREPARAR", bg=PANEL, fg=TEXT, font=("Inter", 10, "bold")).pack(anchor="w")
        tk.Label(
            notes,
            text="1. No Lutris, abra o Rockstar Games Launcher usando este prefixo.\n"
                 "2. Inicie GTA V Enhanced e chegue ao modo história pelo menos uma vez.\n"
                 "3. Feche o jogo e o Rockstar Launcher completamente.\n"
                 "4. Selecione o prefixo e a pasta do jogo; clique em Preparar.\n\n"
                 "Limitação confirmada: o botão Connect falha em resolveServer() antes de chamar connectTo. Não é um erro dos caminhos ou do prefixo.\n\n"
                 "A autenticação por links cfx:// também não é concluída no Wine: o callback não chega à instância aberta (erro 50 em named pipes). O 401 em /api/identities é apenas associação opcional de contas.\n\n"
                 "Esta versão usa Wine diretamente e ainda não integra UMU; não selecione files/bin/wine do Proton ou GE-Proton.\n\n"
                 "O script cria backup dos arquivos de registro do prefixo antes de alterar configurações.",
            bg=PANEL, fg=MUTED, justify="left", anchor="nw", wraplength=395,
            font=("Inter", 9), pady=9
        ).pack(fill="both", expand=True, anchor="w")

        logframe = tk.Frame(lower, bg=PANEL, padx=12, pady=10)
        logframe.pack(side="left", fill="both", expand=True, padx=(7, 0))
        tk.Label(logframe, text="ATIVIDADE", bg=PANEL, fg=TEXT, font=("Inter", 10, "bold")).pack(anchor="w")
        self.logbox = tk.Text(logframe, height=9, bg="#0e131c", fg="#d2dbe8", insertbackground=TEXT,
                              relief="flat", borderwidth=0, wrap="word", font=("JetBrains Mono", 8), padx=9, pady=8)
        self.logbox.pack(fill="both", expand=True, pady=(8, 0))
        self.logbox.configure(state="disabled")
        self.log("App iniciado. Se a detecção automática não localizar o jogo, selecione as pastas manualmente.")
        tk.Label(outer, text="Projeto comunitário experimental • sem bypass de anti-cheat • não afiliado à Cfx.re ou Rockstar",
                 bg=BG, fg="#64748b", font=("Inter", 8)).pack(anchor="w", pady=(10, 0))

    def add_path_row(self, parent, label, variable, command):
        tk.Label(parent, text=label, bg=PANEL, fg=MUTED, font=("Inter", 8, "bold")).pack(anchor="w", pady=(4, 5))
        row = tk.Frame(parent, bg=PANEL)
        row.pack(fill="x", pady=(0, 6))
        entry = ttk.Entry(row, textvariable=variable, state="readonly")
        entry.pack(side="left", fill="x", expand=True, ipady=5)
        btn = self.button(row, "ESCOLHER", command)
        btn.pack(side="left", padx=(8, 0))
        self.path_buttons.append(btn)
        return entry

    def log(self, message: str):
        self.events.put(("log", f"[{time.strftime('%H:%M:%S')}] {message.rstrip()}"))

    def on_close(self):
        if self.busy:
            messagebox.showwarning(
                "Preparação em andamento",
                "A preparação está modificando o prefixo do Lutris. Aguarde a conclusão antes de fechar o aplicativo.",
                parent=self.root,
            )
            return
        self.root.destroy()

    def poll_events(self):
        try:
            while True:
                kind, payload = self.events.get_nowait()
                if kind == "log":
                    self.logbox.configure(state="normal")
                    self.logbox.insert("end", payload + "\n")
                    self.logbox.see("end")
                    self.logbox.configure(state="disabled")
                elif kind == "status":
                    self.status_var.set(payload[0])
                    if payload[1]:
                        self.detail_var.set(payload[1])
                elif kind == "error":
                    messagebox.showerror("FiveM on Linux", payload, parent=self.root)
                elif kind == "info":
                    messagebox.showinfo("FiveM on Linux", payload, parent=self.root)
                elif kind == "done":
                    self.busy = False
                    self.progress.stop()
                    for btn in (self.prepare_btn, self.launch_btn, self.open_prefix_btn, self.refresh_btn, *self.path_buttons):
                        btn.configure(state="normal")
                    self.refresh_status()
        except queue.Empty:
            pass
        self.root.after(120, self.poll_events)

    def load_settings_and_detect(self):
        saved = {}
        try:
            loaded = json.loads(SETTINGS_FILE.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                saved = loaded
        except (OSError, json.JSONDecodeError):
            pass
        detected_prefix, detected_game, detected_wine = detect_defaults()
        prefix = expand_path(saved["prefix"]) if saved.get("prefix") else detected_prefix
        game = expand_path(saved["game"]) if saved.get("game") else detected_game
        wine = expand_path(saved["wine"]) if saved.get("wine") else detected_wine
        if prefix and is_prefix(prefix):
            self.prefix_var.set(str(prefix))
        if game and has_game(game):
            self.game_var.set(str(game))
        if wine and wine.is_file():
            self.wine_var.set(str(wine))
        self.log(f"Detecção do Lutris: prefixo={'encontrado' if self.prefix_var.get() else 'não encontrado'}, jogo={'encontrado' if self.game_var.get() else 'seleção manual necessária'}, Wine={'encontrado' if self.wine_var.get() else 'não encontrado'}.")

    def browse_prefix(self):
        selected = filedialog.askdirectory(title="Selecione o prefixo configurado no Lutris", mustexist=True, parent=self.root)
        if not selected:
            return
        path = Path(selected).expanduser().resolve()
        if not is_prefix(path):
            messagebox.showerror("Prefixo inválido", "Selecione a pasta que contém drive_c/ e system.reg. Não selecione a pasta drive_c em si.", parent=self.root)
            return
        self.prefix_var.set(str(path))
        self.log(f"Prefixo selecionado: {path}")
        self.refresh_status()

    def browse_game(self):
        selected = filedialog.askdirectory(title="Selecione a pasta do GTA V Enhanced", mustexist=True, parent=self.root)
        if not selected:
            return
        path = Path(selected).expanduser().resolve()
        if not has_game(path):
            messagebox.showerror("Pasta do jogo inválida", "Não encontrei GTA5_Enhanced.exe nessa pasta. Selecione a pasta principal do GTA V Enhanced.", parent=self.root)
            return
        self.game_var.set(str(path))
        self.log(f"Pasta do jogo selecionada: {path}")
        self.refresh_status()

    def browse_wine(self):
        candidates = wine_candidates()
        initial = str(candidates[0].parent) if candidates else str(HOME)
        selected = filedialog.askopenfilename(
            title="Selecione bin/wine do runner configurado no Lutris",
            initialdir=initial,
            filetypes=[("Wine executable", "wine"), ("All files", "*")],
            parent=self.root
        )
        if not selected:
            return
        path = Path(selected).expanduser().resolve()
        if not path.is_file() or not os.access(path, os.X_OK):
            messagebox.showerror("Wine inválido", "Selecione um executável Wine que exista e seja executável.", parent=self.root)
            return
        if is_proton_runner(path):
            messagebox.showerror(
                "Proton não suportado diretamente",
                "Este aplicativo chama wine/wineserver diretamente e não inicia o runtime UMU. "
                "Não selecione files/bin/wine do Proton ou GE-Proton: fora da Steam, esses runners "
                "devem ser executados pelo UMU. Use um runner Wine do Lutris nesta versão do aplicativo.",
                parent=self.root,
            )
            return
        self.wine_var.set(str(path))
        self.log(f"Runner Wine selecionado: {path}")
        self.refresh_status()

    def selected_paths(self):
        prefix = expand_path(self.prefix_var.get())
        game = expand_path(self.game_var.get())
        wine = expand_path(self.wine_var.get())
        errors = []
        if not is_prefix(prefix):
            errors.append("Prefixo: selecione a pasta correta do Lutris (contém drive_c e system.reg).")
        if not has_game(game):
            errors.append("Jogo: selecione a pasta que contém GTA5_Enhanced.exe.")
        elif not os.access(game / GAME_EXE, os.R_OK):
            errors.append("Jogo: o executável GTA5_Enhanced.exe não pode ser lido por este usuário.")
        if is_prefix(prefix) and not os.access(prefix, os.W_OK):
            errors.append("Prefixo: sem permissão de escrita. Verifique as permissões da pasta do Lutris.")
        if not wine.is_file() or not os.access(wine, os.X_OK):
            errors.append("Wine: selecione o executável Wine do runner configurado no Lutris.")
        elif is_proton_runner(wine):
            errors.append(
                "Proton/GE-Proton não pode ser executado diretamente por este instalador. "
                "Ele exige o runtime UMU, que esta versão ainda não integra. Selecione um runner Wine do Lutris."
            )
        if errors:
            raise ValueError("\n".join(errors))
        server = wineserver_for(wine)
        if not server:
            raise ValueError("Não encontrei o wineserver correspondente ao Wine selecionado. Selecione o executável bin/wine do runner correto no Lutris; não será usado um wineserver de outra versão.")
        return prefix.resolve(), game.resolve(), wine.resolve(), server

    def env_for(self, paths):
        prefix, game, wine, server = paths
        runtime = runner_root(wine)
        env = os.environ.copy()
        env.update({
            "WINEPREFIX": str(prefix),
            "GTA_ENHANCED_DIR": str(game),
            "WINE": str(wine),
            "WINESERVER": str(server),
            "LUTRIS_RUNNER_DIR": str(runtime),
            "WINE_USER": profile_for_prefix(prefix),
            "FIVEM_ROOT": str(RUNTIME_ROOT),
            "FIVEM_GAME_PLATFORM": "rockstar",
            "WINEDEBUG": "-all",
        })
        return env

    def atomic_write(self, path: Path, content: str, mode: int = 0o600):
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
        try:
            temporary.write_text(content, encoding="utf-8")
            temporary.chmod(mode)
            os.replace(temporary, path)
        finally:
            try:
                temporary.unlink()
            except FileNotFoundError:
                pass

    def save_settings(self, paths):
        prefix, game, wine, server = paths
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        self.atomic_write(SETTINGS_FILE, json.dumps({
            "prefix": str(prefix), "game": str(game), "wine": str(wine)
        }, indent=2) + "\n")
        env = self.env_for(paths)
        exports = [
            "WINEPREFIX", "GTA_ENHANCED_DIR", "WINE", "WINESERVER",
            "LUTRIS_RUNNER_DIR", "WINE_USER", "FIVEM_ROOT",
            "FIVEM_GAME_PLATFORM", "WINEDEBUG"
        ]
        env_content = "".join(f"export {key}={shlex.quote(env[key])}\n" for key in exports)
        self.atomic_write(ENV_FILE, env_content)
        self.create_launchers()

    def create_launchers(self):
        launch_script = HOME / ".local/share/fivem-linux/launch-lutris.sh"
        cfx_script = HOME / ".local/share/fivem-linux/launch-cfx-url.sh"
        launch_script.parent.mkdir(parents=True, exist_ok=True)
        envfile = str(ENV_FILE)
        launch_script.write_text(
            "#!/usr/bin/env bash\nset -Eeuo pipefail\nset -a\nsource " + shlex.quote(envfile) +
            "\nset +a\nexec bash " + shlex.quote(str(VENDOR_BIN / "launch.sh")) + ' "$@"\n',
            encoding="utf-8"
        )
        launch_script.chmod(0o755)
        cfx_script.write_text(
            "#!/usr/bin/env bash\nset -Eeuo pipefail\nset -a\nsource " + shlex.quote(envfile) +
            "\nset +a\nexec bash " + shlex.quote(str(VENDOR_BIN / "cfx-url-handler.sh")) + ' "$@"\n',
            encoding="utf-8"
        )
        cfx_script.chmod(0o755)
        apps = HOME / ".local/share/applications"
        apps.mkdir(parents=True, exist_ok=True)
        desktop = apps / "fivem-enhanced-lutris.desktop"
        desktop.write_text(
            "[Desktop Entry]\nType=Application\nName=FiveM Enhanced (Lutris)\n"
            "Comment=FiveM Enhanced usando o prefixo Rockstar do Lutris\n"
            'Exec="/usr/bin/env" "bash" "' + str(launch_script).replace('"', '\\"') + '"\n'
            "Icon=applications-games\nTerminal=false\nCategories=Game;\nStartupNotify=true\n",
            encoding="utf-8"
        )
        cfx_desktop = apps / "fivem-enhanced-lutris-cfx.desktop"
        cfx_desktop.write_text(
            "[Desktop Entry]\nType=Application\nName=FiveM Enhanced cfx URL handler (Lutris)\n"
            'Exec="/usr/bin/env" "bash" "' + str(cfx_script).replace('"', '\\"') + '" "%u"\n'
            "Icon=applications-games\nTerminal=false\nNoDisplay=true\nMimeType=x-scheme-handler/cfx;\n",
            encoding="utf-8"
        )
        try:
            previous_handler = CONFIG_DIR / "cfx-handler.previous"
            if not previous_handler.exists():
                previous = subprocess.run(
                    ["xdg-mime", "query", "default", "x-scheme-handler/cfx"],
                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                    text=True, check=False
                )
                previous_name = previous.stdout.strip() if previous.returncode == 0 else ""
                # A handler left by an older install of this project is not a
                # pre-existing application; do not restore a desktop file we remove.
                if previous_name == cfx_desktop.name:
                    previous_name = ""
                self.atomic_write(previous_handler, (previous_name or "__NONE__") + "\n")
            subprocess.run(["xdg-mime", "default", cfx_desktop.name, "x-scheme-handler/cfx"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        except OSError:
            self.log("Não foi possível registrar o handler cfx:// no desktop.")
        self.log(f"Atalho de desktop criado: {desktop}")

    def run_background(self, title, action):
        if self.busy:
            return
        self.busy = True
        for btn in (self.prepare_btn, self.launch_btn, self.open_prefix_btn, self.refresh_btn, *self.path_buttons):
            btn.configure(state="disabled")
        self.progress.start(10)
        self.status_var.set(title)
        threading.Thread(target=self.worker, args=(action,), daemon=True).start()

    def worker(self, action):
        try:
            action()
        except Exception as exc:
            self.events.put(("error", str(exc)))
            self.log(f"ERRO: {exc}")
        finally:
            self.events.put(("done", None))

    def run_installer(self, env):
        if not INSTALL_SCRIPT.is_file():
            raise RuntimeError(f"Script não encontrado: {INSTALL_SCRIPT}")
        self.log("Executando preparação no prefixo existente. Isso pode baixar vários componentes.")
        process = subprocess.Popen(
            ["bash", str(INSTALL_SCRIPT)], cwd=str(VENDOR_DIR), env=env,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1
        )
        assert process.stdout is not None
        for line in process.stdout:
            self.log(line.rstrip())
        code = process.wait()
        if code != 0:
            raise RuntimeError(f"O script terminou com código {code}. Consulte a área Atividade. Os backups ficam em {RUNTIME_ROOT / 'backups'}.")
        paths = (
            Path(env["WINEPREFIX"]), Path(env["GTA_ENHANCED_DIR"]),
            Path(env["WINE"]), Path(env["WINESERVER"])
        )
        self.save_settings(paths)
        self.events.put(("status", ("Preparação concluída", "FiveM foi preparado no prefixo selecionado do Lutris.")))
        self.events.put(("info", "Preparação concluída.\n\nUse ABRIR FIVEM ou o atalho 'FiveM Enhanced (Lutris)' no menu de aplicativos. A primeira inicialização pode demorar porque o cliente baixa o cache necessário."))

    def prepare(self):
        try:
            paths = self.selected_paths()
        except ValueError as exc:
            messagebox.showerror("Configuração incompleta", str(exc), parent=self.root)
            return
        prefix, game, wine, server = paths
        launcher_paths = [
            prefix / "drive_c/Program Files/Rockstar Games/Launcher/Launcher.exe",
            prefix / "drive_c/Program Files (x86)/Rockstar Games/Launcher/Launcher.exe"
        ]
        if not any(p.exists() for p in launcher_paths):
            proceed = messagebox.askyesno(
                "Launcher Rockstar não detectado",
                "Não encontrei o executável do Rockstar Games Launcher nesse prefixo.\n\n"
                "Confirme que esse é o prefixo usado pelo Lutris para abrir o Rockstar Launcher e GTA V Enhanced.\n\nContinuar mesmo assim?",
                parent=self.root
            )
            if not proceed:
                return
        accepted = messagebox.askyesno(
            "Preparar FiveM no prefixo do Lutris",
            "A preparação vai modificar registros e adicionar componentes ao prefixo escolhido.\n"
            "O script faz backup de system.reg/user.reg/userdef.reg e de DLLs encontradas antes de alterá-los.\n\n"
            "Feche GTA V, Rockstar Games Launcher e qualquer outro programa usando esse prefixo antes de continuar.\n\n"
            "Os arquivos do jogo não serão baixados novamente nem substituídos. Continuar?",
            parent=self.root
        )
        if not accepted:
            return
        env = self.env_for(paths)
        self.save_settings(paths)
        self.run_background("Preparando FiveM para o Lutris...", lambda: self.run_installer(env))

    def launch(self):
        try:
            paths = self.selected_paths()
        except ValueError as exc:
            messagebox.showerror("Configuração incompleta", str(exc), parent=self.root)
            return
        prefix, game, wine, server = paths
        exe = prefix / FIVEM_EXE_REL
        if not exe.is_file():
            messagebox.showinfo("FiveM ainda não preparado", "Clique primeiro em PREPARAR NESTE PREFIXO.", parent=self.root)
            return
        env = self.env_for(paths)
        self.save_settings(paths)
        script = HOME / ".local/share/fivem-linux/launch-lutris.sh"
        try:
            subprocess.Popen(["bash", str(script)], env=os.environ.copy(), start_new_session=True)
            self.log("FiveM iniciado pelo Wine runner selecionado no Lutris.")
        except OSError as exc:
            messagebox.showerror("Falha ao iniciar", str(exc), parent=self.root)

    def open_prefix(self):
        try:
            prefix = expand_path(self.prefix_var.get())
            if not is_prefix(prefix):
                raise ValueError("Selecione uma pasta de prefixo válida.")
            subprocess.Popen(["xdg-open", str(prefix)])
        except (OSError, ValueError) as exc:
            messagebox.showerror("Não foi possível abrir", str(exc), parent=self.root)

    def refresh_status(self):
        prefix = expand_path(self.prefix_var.get()) if self.prefix_var.get() else None
        game = expand_path(self.game_var.get()) if self.game_var.get() else None
        wine = expand_path(self.wine_var.get()) if self.wine_var.get() else None
        if game and has_game(game):
            self.status_cards["Jogo"].configure(text="GTA V Enhanced localizado", fg=GREEN)
        else:
            self.status_cards["Jogo"].configure(text="Selecione a pasta do jogo", fg=ACCENT)
        if prefix and is_prefix(prefix):
            self.status_cards["Prefixo Lutris"].configure(text=str(prefix), fg=GREEN)
        else:
            self.status_cards["Prefixo Lutris"].configure(text="Selecione o prefixo com system.reg", fg=ACCENT)
        wine_ok = bool(
            wine and wine.is_file() and os.access(wine, os.X_OK)
            and not is_proton_runner(wine) and wineserver_for(wine)
        )
        if wine_ok:
            self.status_cards["Runner Wine"].configure(text="Wine + wineserver correspondentes", fg=GREEN)
        elif wine and is_proton_runner(wine):
            self.status_cards["Runner Wine"].configure(text="Proton selecionado sem integração UMU", fg=ACCENT)
        else:
            self.status_cards["Runner Wine"].configure(text="Wine ou wineserver correspondente ausente", fg=ACCENT)
        if prefix and is_prefix(prefix) and (prefix / FIVEM_EXE_REL).is_file():
            self.status_cards["FiveM Enhanced"].configure(text="Arquivos instalados", fg=GREEN)
        else:
            self.status_cards["FiveM Enhanced"].configure(text="Ainda não preparado", fg=MUTED)

        if prefix and is_prefix(prefix) and game and has_game(game) and wine_ok:
            self.status_var.set("Configuração encontrada")
            self.detail_var.set(f"Prefixo: {prefix}  •  Jogo: {game}")
        else:
            self.status_var.set("Selecione ou confirme os três caminhos")
            self.detail_var.set("O jogo e o prefixo podem estar em discos diferentes. Use ESCOLHER em cada campo.")

def main():
    try:
        root = tk.Tk()
        FiveMLutrisApp(root)
        root.mainloop()
    except tk.TclError as exc:
        print(f"Não foi possível abrir a interface gráfica: {exc}", file=__import__("sys").stderr)
        raise


if __name__ == "__main__":
    main()
