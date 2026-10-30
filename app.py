#!/usr/bin/env python3
"""Visual setup helper for FiveM Enhanced on Steam/Proton under Linux."""
from __future__ import annotations

import json
import os
import queue
import re
import shutil
import struct
import subprocess
import tarfile
import tempfile
import threading
import time
import urllib.error
import urllib.request
import zlib
from pathlib import Path
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

APP_ID = "3240220"
APP_NAME = "FiveM Enhanced — Linux"
FIVEM_INSTALLER_URL = "https://depot.cfx.re/public/p/cfxinstaller/u/main/c/FiveM_Installer.exe"
WEBVIEW2_URL = "https://go.microsoft.com/fwlink/p/?LinkId=2124701"
GE_RELEASES_API = "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest"
HOME = Path.home()
CACHE_DIR = HOME / ".cache" / "fivem-linux"
INSTALL_DIR = HOME / ".local" / "share" / "fivem-linux"
LOG_DIR = HOME / ".local" / "state" / "fivem-linux"
GAME_LAUNCH_OPTIONS = "PROTON_USE_XALIA=0 bash -c 'exec \\"" + chr(36) + "{@//waitforexitandrun/run}\\\" -- %command%'"

BG = "#0b0e14"
PANEL = "#141a24"
PANEL_2 = "#1b2432"
TEXT = "#edf2f7"
MUTED = "#9aa9bc"
ACCENT = "#fb923c"
GREEN = "#4ade80"
RED = "#fb7185"
BLUE = "#93c5fd"


def steam_roots() -> list[Path]:
    candidates = [
        HOME / ".local/share/Steam",
        HOME / ".steam/steam",
        HOME / ".steam/root",
        HOME / ".var/app/com.valvesoftware.Steam/.local/share/Steam",
    ]
    found: list[Path] = []
    seen: set[str] = set()
    for path in candidates:
        if path.exists():
            resolved = path.resolve()
            key = str(resolved)
            if key not in seen:
                found.append(resolved)
                seen.add(key)
    return found


def steam_libraries(root: Path) -> list[Path]:
    result = [root]
    vdf_candidates = [root / "steamapps" / "libraryfolders.vdf", root / "config" / "libraryfolders.vdf"]
    for vdf in vdf_candidates:
        if not vdf.exists():
            continue
        try:
            data = vdf.read_text(encoding="utf-8", errors="replace")
            for value in re.findall(r'"path"\s*"([^"]+)"', data):
                candidate = Path(value.replace("\\\\", "\\"))
                if candidate.exists():
                    result.append(candidate.resolve())
        except OSError:
            pass
    unique: list[Path] = []
    seen: set[str] = set()
    for path in result:
        key = str(path.resolve())
        if key not in seen:
            unique.append(path.resolve())
            seen.add(key)
    return unique


def game_executable(folder: Path) -> bool:
    return (folder / "GTA5_Enhanced.exe").is_file()


def find_game() -> tuple[Path | None, Path | None, Path | None]:
    roots = steam_roots()
    for root in roots:
        for library in steam_libraries(root):
            manifest = library / "steamapps" / f"appmanifest_{APP_ID}.acf"
            if manifest.is_file():
                try:
                    text = manifest.read_text(encoding="utf-8", errors="replace")
                    match = re.search(r'"installdir"\s*"([^"]+)"', text)
                    install_dir = match.group(1) if match else "Grand Theft Auto V Enhanced"
                except OSError:
                    install_dir = "Grand Theft Auto V Enhanced"
                folder = library / "steamapps" / "common" / install_dir
                if game_executable(folder):
                    return folder.resolve(), library, root
            common = library / "steamapps" / "common"
            for name in ("Grand Theft Auto V Enhanced", "Grand Theft Auto V"):
                candidate = common / name
                if game_executable(candidate):
                    return candidate.resolve(), library, root
            if common.is_dir():
                try:
                    for candidate in common.iterdir():
                        if candidate.is_dir() and "enhanced" in candidate.name.lower() and game_executable(candidate):
                            return candidate.resolve(), library, root
                except OSError:
                    pass
    return None, None, roots[0] if roots else None


def library_from_game(folder: Path) -> Path | None:
    parents = list(folder.parents)
    for index in range(len(parents) - 1):
        if parents[index].name == "common" and parents[index + 1].name == "steamapps":
            return parents[index + 1].parent
    return None


def find_prefix_base(library: Path | None, root: Path | None) -> Path | None:
    candidates: list[Path] = []
    if library:
        candidates.append(library / "steamapps" / "compatdata" / APP_ID)
    for steam_root in steam_roots():
        candidates.append(steam_root / "steamapps" / "compatdata" / APP_ID)
        for lib in steam_libraries(steam_root):
            candidates.append(lib / "steamapps" / "compatdata" / APP_ID)
    if root:
        candidates.append(root / "steamapps" / "compatdata" / APP_ID)
    unique: list[Path] = []
    seen: set[str] = set()
    for item in candidates:
        key = str(item.resolve(strict=False))
        if key not in seen:
            unique.append(item)
            seen.add(key)
    for item in unique:
        if (item / "pfx" / "drive_c").is_dir():
            return item
    return unique[0] if unique else None


def proton_candidates() -> list[tuple[str, Path, Path]]:
    results: list[tuple[str, Path, Path]] = []
    for root in steam_roots():
        for folder in (root / "compatibilitytools.d", root / "steamapps" / "common"):
            if folder.is_dir():
                for path in folder.glob("GE-Proton*/proton"):
                    results.append((path.parent.name, path, root))
                for name in ("Proton - Experimental", "Proton 10.0", "Proton 9.0", "Proton 8.0"):
                    path = folder / name / "proton"
                    if path.is_file():
                        results.append((path.parent.name, path, root))
    def version_key(item: tuple[str, Path, Path]) -> tuple[int, ...]:
        return tuple(int(n) for n in re.findall(r"\d+", item[0])) or (0,)
    ge = sorted((p for p in results if p[0].startswith("GE-Proton")), key=version_key, reverse=True)
    other = sorted((p for p in results if not p[0].startswith("GE-Proton")), key=lambda p: (0 if "Experimental" in p[0] else 1, version_key(p)), reverse=False)
    unique: list[tuple[str, Path, Path]] = []
    seen: set[str] = set()
    for item in ge + other:
        key = str(item[1].resolve())
        if key not in seen:
            unique.append(item)
            seen.add(key)
    return unique


def runtime_path(root: Path) -> Path | None:
    names = ("SteamLinuxRuntime_4", "SteamLinuxRuntime_sniper", "SteamLinuxRuntime_soldier")
    for name in names:
        path = root / "steamapps" / "common" / name / "run"
        if path.is_file():
            return path
    return None


def steam_running() -> bool:
    try:
        result = subprocess.run(["pgrep", "-x", "steam"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        return result.returncode == 0
    except FileNotFoundError:
        try:
            output = subprocess.check_output(["ps", "-eo", "comm="], text=True)
            return any(line.strip() == "steam" for line in output.splitlines())
        except Exception:
            return False


def read_cstring(data: bytes, pos: int) -> tuple[str, int]:
    end = data.find(b"\0", pos)
    if end < 0:
        raise ValueError("Arquivo shortcuts.vdf inválido: string sem terminador.")
    return data[pos:end].decode("utf-8", errors="replace"), end + 1


def parse_binary_object(data: bytes, pos: int) -> tuple[dict, int]:
    output: dict = {}
    while pos < len(data):
        kind = data[pos]
        pos += 1
        if kind == 8:
            return output, pos
        key, pos = read_cstring(data, pos)
        if kind == 0:
            value, pos = parse_binary_object(data, pos)
        elif kind == 1:
            value, pos = read_cstring(data, pos)
        elif kind == 2:
            value = struct.unpack_from("<i", data, pos)[0]
            pos += 4
        elif kind == 3:
            value = struct.unpack_from("<f", data, pos)[0]
            pos += 4
        elif kind in (4, 6):
            value = data[pos:pos + 4]
            pos += 4
        elif kind == 5:
            end = pos
            while end + 1 < len(data) and data[end:end + 2] != b"\0\0":
                end += 2
            value = data[pos:end].decode("utf-16le", errors="replace")
            pos = end + 2
        elif kind in (7, 9):
            value = struct.unpack_from("<q", data, pos)[0]
            pos += 8
        else:
            raise ValueError(f"Tipo binário VDF não reconhecido: {kind}")
        output[key] = value
    raise ValueError("Arquivo shortcuts.vdf truncado.")


def parse_binary_vdf(data: bytes) -> dict:
    if not data:
        return {"shortcuts": {}}
    if data[0] != 0:
        raise ValueError("O arquivo não parece um VDF binário Steam.")
    root_key, pos = read_cstring(data, 1)
    if root_key.lower() != "shortcuts":
        raise ValueError("VDF sem a raiz shortcuts.")
    root, _ = parse_binary_object(data, pos)
    return {"shortcuts": root}


def encode_vdf_pair(key: str, value) -> bytes:
    key_bytes = key.encode("utf-8") + b"\0"
    if isinstance(value, dict):
        body = b"".join(encode_vdf_pair(str(k), v) for k, v in value.items())
        return b"\x00" + key_bytes + body + b"\x08"
    if isinstance(value, float):
        return b"\x03" + key_bytes + struct.pack("<f", value)
    if isinstance(value, int):
        value = max(-2147483648, min(2147483647, value))
        return b"\x02" + key_bytes + struct.pack("<i", value)
    if isinstance(value, bytes):
        if len(value) == 4:
            return b"\x06" + key_bytes + value
        value = value.hex()
    return b"\x01" + key_bytes + str(value).encode("utf-8") + b"\0"


def serialize_binary_vdf(root: dict) -> bytes:
    shortcuts = root.get("shortcuts", {})
    body = b"".join(encode_vdf_pair(str(key), value) for key, value in shortcuts.items())
    return b"\x00shortcuts\0" + body + b"\x08\x08"


def get_key(mapping: dict, key: str, default=None):
    target = key.casefold()
    for name, value in mapping.items():
        if str(name).casefold() == target:
            return value
    return default


def signed_appid(exe_value: str, name: str) -> int:
    value = (zlib.crc32((exe_value + name).encode("utf-8")) | 0x80000000) & 0xFFFFFFFF
    return value - 0x100000000 if value >= 0x80000000 else value


class FiveMLinuxApp:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.events: queue.Queue = queue.Queue()
        self.busy = False
        self.game_dir: Path | None = None
        self.library_dir: Path | None = None
        self.steam_root: Path | None = None
        self.prefix_base: Path | None = None
        self.proton: Path | None = None
        self.proton_name: str | None = None
        self.fivem_exe: Path | None = None
        self.shortcut_appid: int | None = None
        self.path_var = tk.StringVar()
        self.status_var = tk.StringVar(value="Procurando GTA V Enhanced...")
        self.detail_var = tk.StringVar(value="Steam nativa • CachyOS • KDE Plasma")
        self.init_style()
        self.build_ui()
        self.refresh_status()
        self.root.after(150, self.poll_events)

    def init_style(self):
        self.root.title("FiveM on Linux")
        self.root.geometry("930x760")
        self.root.minsize(800, 650)
        self.root.configure(bg=BG)
        style = ttk.Style(self.root)
        style.theme_use("clam")
        style.configure("TLabel", background=BG, foreground=TEXT, font=("Inter", 10))
        style.configure("Muted.TLabel", background=BG, foreground=MUTED, font=("Inter", 9))
        style.configure("Card.TLabel", background=PANEL, foreground=TEXT, font=("Inter", 10))
        style.configure("Title.TLabel", background=BG, foreground=TEXT, font=("Inter", 23, "bold"))
        style.configure("Section.TLabel", background=PANEL, foreground=TEXT, font=("Inter", 11, "bold"))
        style.configure("TEntry", fieldbackground=PANEL_2, foreground=TEXT, bordercolor=PANEL_2, insertcolor=TEXT)
        style.configure("TProgressbar", troughcolor=PANEL_2, background=ACCENT, bordercolor=PANEL_2)
        style.configure("Vertical.TScrollbar", background=PANEL_2, troughcolor=PANEL)

    def button(self, parent, text, command, primary=False, width=None):
        bg = ACCENT if primary else PANEL_2
        fg = "#111827" if primary else TEXT
        return tk.Button(
            parent, text=text, command=command, width=width,
            bg=bg, fg=fg, activebackground=ACCENT if primary else "#2a3546",
            activeforeground=fg, relief="flat", borderwidth=0, padx=13, pady=9,
            cursor="hand2", font=("Inter", 9, "bold"), disabledforeground="#6b7280"
        )

    def card(self, parent, title: str, value: str):
        frame = tk.Frame(parent, bg=PANEL, padx=14, pady=12, highlightthickness=1, highlightbackground="#222c3b")
        tk.Label(frame, text=title.upper(), bg=PANEL, fg=MUTED, font=("Inter", 8, "bold")).pack(anchor="w")
        label = tk.Label(frame, text=value, bg=PANEL, fg=TEXT, font=("Inter", 10, "bold"), wraplength=240, justify="left")
        label.pack(anchor="w", pady=(7, 0))
        return frame, label

    def build_ui(self):
        outer = tk.Frame(self.root, bg=BG, padx=22, pady=20)
        outer.pack(fill="both", expand=True)
        header = tk.Frame(outer, bg=BG)
        header.pack(fill="x")
        logo = tk.Label(header, text="F", bg=ACCENT, fg="#111827", font=("Inter", 20, "bold"), width=2, height=1)
        logo.pack(side="left", padx=(0, 12))
        titlebox = tk.Frame(header, bg=BG)
        titlebox.pack(side="left", fill="x", expand=True)
        ttk.Label(titlebox, text="FiveM on Linux", style="Title.TLabel").pack(anchor="w")
        ttk.Label(titlebox, text="GTA V ENHANCED  /  STEAM + PROTON", style="Muted.TLabel").pack(anchor="w", pady=(3, 0))
        self.button(header, "ATUALIZAR STATUS", self.refresh_status).pack(side="right", padx=(8, 0))
        tk.Frame(outer, bg="#263144", height=1).pack(fill="x", pady=17)

        hero = tk.Frame(outer, bg=PANEL, padx=18, pady=15, highlightthickness=1, highlightbackground="#263144")
        hero.pack(fill="x")
        ttk.Label(hero, textvariable=self.status_var, style="Section.TLabel").pack(anchor="w")
        ttk.Label(hero, textvariable=self.detail_var, style="Muted.TLabel").pack(anchor="w", pady=(5, 0))
        self.progress = ttk.Progressbar(hero, mode="indeterminate")
        self.progress.pack(fill="x", pady=(13, 0))

        loc = tk.Frame(outer, bg=PANEL, padx=16, pady=13, highlightthickness=1, highlightbackground="#263144")
        loc.pack(fill="x", pady=(13, 0))
        tk.Label(loc, text="LOCALIZAÇÃO DO GTA V ENHANCED", bg=PANEL, fg=MUTED, font=("Inter", 8, "bold")).pack(anchor="w")
        pathrow = tk.Frame(loc, bg=PANEL)
        pathrow.pack(fill="x", pady=(8, 0))
        self.path_entry = ttk.Entry(pathrow, textvariable=self.path_var)
        self.path_entry.pack(side="left", fill="x", expand=True, ipady=5)
        self.button(pathrow, "ESCOLHER PASTA", self.browse_game).pack(side="left", padx=(8, 0))
        self.button(pathrow, "DETECTAR", self.detect_button).pack(side="left", padx=(8, 0))

        cards = tk.Frame(outer, bg=BG)
        cards.pack(fill="x", pady=(13, 0))
        self.card_labels = {}
        items = [
            ("GTA V Enhanced", "Não encontrado"),
            ("Prefixo Proton", "Não criado"),
            ("FiveM", "Não instalado"),
            ("WebView2", "Verificando"),
        ]
        for index, (name, value) in enumerate(items):
            frame, label = self.card(cards, name, value)
            frame.grid(row=index // 2, column=index % 2, sticky="nsew", padx=(0 if index % 2 == 0 else 7, 7 if index % 2 == 0 else 0), pady=4)
            cards.grid_columnconfigure(index % 2, weight=1)
            self.card_labels[name] = label

        actions = tk.Frame(outer, bg=BG)
        actions.pack(fill="x", pady=(13, 7))
        self.prepare_btn = self.button(actions, "PREPARAR FIVEM", lambda: self.run_worker(self.prepare_fivem), primary=True)
        self.prepare_btn.pack(side="left")
        self.ge_btn = self.button(actions, "INSTALAR GE-PROTON", lambda: self.run_worker(self.install_ge_proton))
        self.ge_btn.pack(side="left", padx=(8, 0))
        self.shortcut_btn = self.button(actions, "REGISTRAR ATALHO STEAM", self.register_shortcut)
        self.shortcut_btn.pack(side="left", padx=(8, 0))
        self.launch_btn = self.button(actions, "ABRIR FIVEM", self.launch_fivem)
        self.launch_btn.pack(side="right")

        lower = tk.Frame(outer, bg=BG)
        lower.pack(fill="both", expand=True, pady=(8, 0))
        notes = tk.Frame(lower, bg=PANEL, padx=14, pady=12)
        notes.pack(side="left", fill="both", expand=True, padx=(0, 7))
        tk.Label(notes, text="PASSOS IMPORTANTES", bg=PANEL, fg=TEXT, font=("Inter", 10, "bold")).pack(anchor="w")
        tk.Label(
            notes,
            text="1. Inicie o GTA Enhanced pela Steam uma vez e entre no modo história.\n"
                 "2. Use Preparar FiveM e conclua o instalador que abrir.\n"
                 "3. Feche a Steam para registrar o atalho; depois reabra.\n"
                 "4. Ative a mesma versão de Proton nas propriedades do GTA e do atalho.\n\n"
                 "Experimental: abrir o launcher não garante conexão a servidores.",
            bg=PANEL, fg=MUTED, justify="left", anchor="nw", wraplength=380,
            font=("Inter", 9), pady=9
        ).pack(fill="both", expand=True, anchor="w")
        logframe = tk.Frame(lower, bg=PANEL, padx=12, pady=10)
        logframe.pack(side="left", fill="both", expand=True, padx=(7, 0))
        tk.Label(logframe, text="ATIVIDADE", bg=PANEL, fg=TEXT, font=("Inter", 10, "bold")).pack(anchor="w")
        self.logbox = tk.Text(logframe, height=8, bg="#0e131c", fg="#d2dbe8", insertbackground=TEXT,
                              relief="flat", borderwidth=0, wrap="word", font=("JetBrains Mono", 8), padx=9, pady=8)
        self.logbox.pack(fill="both", expand=True, pady=(8, 0))
        self.logbox.configure(state="disabled")
        self.log("Aplicativo iniciado. A detecção automática inclui bibliotecas Steam em outros discos.")
        tk.Label(outer, text="Ferramenta experimental de comunidade • não afiliada à Cfx.re, Rockstar ou Valve",
                 bg=BG, fg="#64748b", font=("Inter", 8)).pack(anchor="w", pady=(11, 0))

    def log(self, message: str):
        self.events.put(("log", f"[{time.strftime('%H:%M:%S')}] {message}"))

    def set_status(self, text: str, detail: str | None = None):
        self.events.put(("status", (text, detail)))

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
                    if payload[1] is not None:
                        self.detail_var.set(payload[1])
                elif kind == "error":
                    self.status_var.set("Não foi possível concluir")
                    messagebox.showerror("FiveM on Linux", payload, parent=self.root)
                elif kind == "info":
                    messagebox.showinfo("FiveM on Linux", payload, parent=self.root)
                elif kind == "confirm":
                    title, message, finished, result = payload
                    try:
                        result["value"] = messagebox.askyesno(title, message, parent=self.root)
                    finally:
                        finished.set()
                elif kind == "done":
                    self.busy = False
                    self.progress.stop()
                    self.prepare_btn.configure(state="normal")
                    self.ge_btn.configure(state="normal")
                    self.shortcut_btn.configure(state="normal")
                    self.launch_btn.configure(state="normal")
                    self.refresh_status()
        except queue.Empty:
            pass
        self.root.after(150, self.poll_events)

    def ask_yes_no(self, title: str, message: str) -> bool:
        finished = threading.Event()
        result: dict = {}
        self.events.put(("confirm", (title, message, finished, result)))
        finished.wait()
        return bool(result.get("value", False))

    def run_worker(self, action):
        if self.busy:
            return
        self.busy = True
        self.prepare_btn.configure(state="disabled")
        self.ge_btn.configure(state="disabled")
        self.shortcut_btn.configure(state="disabled")
        self.launch_btn.configure(state="disabled")
        self.progress.start(10)
        threading.Thread(target=self._worker, args=(action,), daemon=True).start()

    def _worker(self, action):
        try:
            action()
        except Exception as exc:
            self.events.put(("error", f"{exc}\n\nSe o erro persistir, envie o conteúdo da área Atividade para um chamado no GitHub."))
            self.log(f"ERRO: {exc}")
        finally:
            self.events.put(("done", None))

    def refresh_status(self):
        path = Path(self.path_var.get()).expanduser() if self.path_var.get().strip() else None
        if path and game_executable(path):
            self.game_dir = path.resolve()
            self.library_dir = library_from_game(self.game_dir) or self.library_dir
        elif self.game_dir and game_executable(self.game_dir):
            path = self.game_dir
        else:
            game, library, root = find_game()
            if game:
                self.game_dir, self.library_dir = game, library
                self.steam_root = root
                self.path_var.set(str(game))
                path = game
        roots = steam_roots()
        if self.steam_root is None:
            self.steam_root = next((r for r in roots if (r / "userdata").is_dir()), roots[0] if roots else None)
        self.prefix_base = find_prefix_base(self.library_dir, self.steam_root)
        pfx = (self.prefix_base / "pfx") if self.prefix_base else None
        local_app = (pfx / "drive_c/users/steamuser/AppData/Local") if pfx else None
        self.fivem_exe = local_app / "FiveM for GTAV Enhanced/FiveM.exe" if local_app else None
        if self.game_dir and game_executable(self.game_dir):
            self.card_labels["GTA V Enhanced"].configure(text="Encontrado")
            self.card_labels["GTA V Enhanced"].configure(fg=GREEN)
        else:
            self.card_labels["GTA V Enhanced"].configure(text="Não encontrado")
            self.card_labels["GTA V Enhanced"].configure(fg=RED)
        if pfx and (pfx / "drive_c").is_dir():
            self.card_labels["Prefixo Proton"].configure(text="Pronto")
            self.card_labels["Prefixo Proton"].configure(fg=GREEN)
        else:
            self.card_labels["Prefixo Proton"].configure(text="Precisa iniciar o jogo")
            self.card_labels["Prefixo Proton"].configure(fg=ACCENT)
        self.shortcut_appid = self.find_existing_shortcut_appid()
        if self.fivem_exe and self.fivem_exe.is_file():
            self.card_labels["FiveM"].configure(text="Instalado")
            self.card_labels["FiveM"].configure(fg=GREEN)
        else:
            self.card_labels["FiveM"].configure(text="Ainda não instalado")
            self.card_labels["FiveM"].configure(fg=ACCENT)
        webview_found = False
        if local_app:
            probes = [
                local_app / "Microsoft/EdgeWebView/Application",
                pfx / "drive_c/Program Files (x86)/Microsoft/EdgeWebView",
                pfx / "drive_c/Program Files/Microsoft/EdgeWebView",
            ]
            webview_found = any(p.exists() and any(p.iterdir()) for p in probes if p.is_dir())
        self.card_labels["WebView2"].configure(text="Encontrado" if webview_found else "Será instalado")
        self.card_labels["WebView2"].configure(fg=GREEN if webview_found else MUTED)
        if self.game_dir and pfx and (pfx / "drive_c").is_dir():
            self.status_var.set("Jogo localizado; pronto para preparar")
            self.detail_var.set(str(self.game_dir))
        elif self.game_dir:
            self.status_var.set("Jogo localizado; falta criar o prefixo Proton")
            self.detail_var.set("Inicie o GTA V Enhanced pela Steam uma vez e entre no modo história.")
        else:
            self.status_var.set("GTA V Enhanced ainda não foi localizado")
            self.detail_var.set("Use Detectar ou Escolher pasta. O jogo pode estar em um HD secundário.")
        candidates = proton_candidates()
        if candidates:
            self.proton_name, self.proton, root = candidates[0]
            if self.steam_root is None:
                self.steam_root = root
            self.log(f"Proton detectado: {self.proton_name}")
        else:
            self.proton_name, self.proton = None, None
            self.log("Nenhum Proton encontrado nos locais conhecidos.")

    def detect_button(self):
        game, library, root = find_game()
        if game:
            self.game_dir, self.library_dir, self.steam_root = game, library, root
            self.path_var.set(str(game))
            self.log(f"Jogo detectado: {game}")
        else:
            self.log("Detecção automática não encontrou GTA5_Enhanced.exe.")
            messagebox.showinfo("Detecção", "Não encontrei GTA V Enhanced nas bibliotecas registradas pela Steam.\nUse Escolher pasta e selecione a pasta que contém GTA5_Enhanced.exe.", parent=self.root)
        self.refresh_status()

    def browse_game(self):
        selected = filedialog.askdirectory(title="Selecione a pasta que contém GTA5_Enhanced.exe", mustexist=True, parent=self.root)
        if not selected:
            return
        folder = Path(selected).expanduser()
        if not game_executable(folder):
            messagebox.showerror("Pasta inválida", "Essa pasta não contém GTA5_Enhanced.exe. Selecione a pasta principal do GTA V Enhanced.", parent=self.root)
            return
        self.game_dir = folder.resolve()
        self.library_dir = library_from_game(self.game_dir)
        self.path_var.set(str(self.game_dir))
        roots = steam_roots()
        self.steam_root = next((r for r in roots if (r / "userdata").is_dir()), roots[0] if roots else None)
        self.prefix_base = find_prefix_base(self.library_dir, self.steam_root)
        self.log(f"Pasta do jogo definida manualmente: {self.game_dir}")
        self.refresh_status()

    def require_paths(self) -> tuple[Path, Path, Path]:
        game_dir = Path(self.path_var.get()).expanduser() if self.path_var.get().strip() else self.game_dir
        if not game_dir or not game_executable(game_dir):
            raise RuntimeError("Selecione a pasta que contém GTA5_Enhanced.exe antes de continuar.")
        self.game_dir = game_dir.resolve()
        self.library_dir = library_from_game(self.game_dir) or self.library_dir
        roots = steam_roots()
        if not self.steam_root:
            self.steam_root = next((r for r in roots if (r / "userdata").is_dir()), roots[0] if roots else None)
        if not self.steam_root:
            raise RuntimeError("Não encontrei uma instalação da Steam nativa. Instale/abra a Steam nativa e tente novamente.")
        prefix = find_prefix_base(self.library_dir, self.steam_root)
        if not prefix:
            raise RuntimeError("Não consegui determinar a pasta compatdata do GTA V Enhanced.")
        self.prefix_base = prefix
        return self.game_dir, prefix, self.steam_root

    def start_game_once(self):
        try:
            subprocess.Popen(["xdg-open", f"steam://run/{APP_ID}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass
        self.log("Solicitei à Steam para abrir GTA V Enhanced. Entre no modo história, feche o jogo e clique em Atualizar status.")

    def prepare_fivem(self):
        game_dir, prefix, root = self.require_paths()
        pfx = prefix / "pfx"
        if not (pfx / "drive_c").is_dir():
            self.start_game_once()
            self.events.put(("info", "O prefixo Proton ainda não existe.\n\nA Steam foi chamada para iniciar GTA V Enhanced. Entre no modo história, feche o jogo e clique em Atualizar status. Depois execute Preparar FiveM novamente."))
            return
        candidates = proton_candidates()
        if not candidates:
            raise RuntimeError("Não encontrei Proton/GE-Proton. Clique em Instalar GE-Proton e, ao terminar, reinicie a Steam.")
        self.proton_name, self.proton, proton_root = candidates[0]
        self.log(f"Usando {self.proton_name} para executar os instaladores.")
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        webview = CACHE_DIR / "MicrosoftEdgeWebView2RuntimeInstallerX64.exe"
        if not webview.exists() or webview.stat().st_size < 1024 * 1024:
            self.download(WEBVIEW2_URL, webview, "WebView2 Runtime (Microsoft)")
        self.log("Instalando WebView2 no prefixo do GTA V Enhanced...")
        command = self.prefix_command(webview, ["/silent", "/install"], "wininet=builtin")
        result = subprocess.run(command, env=self.prefix_env("wininet=builtin"), stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, timeout=900, check=False)
        if result.stdout:
            self.write_log_file("webview2.log", result.stdout[-12000:])
        self.log(f"Instalador WebView2 finalizado (código {result.returncode}).")
        installer = CACHE_DIR / "FiveM_Enhanced_Installer.exe"
        if not installer.exists() or installer.stat().st_size < 100 * 1024:
            self.download(FIVEM_INSTALLER_URL, installer, "Instalador oficial FiveM Enhanced")
        self.log("Abrindo instalador FiveM. Conclua as etapas na janela Windows que aparecer.")
        subprocess.Popen(self.prefix_command(installer, [], "wininet=builtin"),
                         env=self.prefix_env("wininet=builtin"), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.events.put(("info", "O instalador do FiveM foi aberto dentro do prefixo do GTA V Enhanced.\n\nConclua o assistente de instalação. Depois volte ao app e clique em Atualizar status. Se a janela não aparecer, veja a área Atividade."))

    def prefix_env(self, dll_overrides: str) -> dict:
        game_dir, prefix, root = self.require_paths()
        env = os.environ.copy()
        env.update({
            "STEAM_COMPAT_CLIENT_INSTALL_PATH": str(root),
            "STEAM_COMPAT_DATA_PATH": str(prefix),
            "STEAM_COMPAT_INSTALL_PATH": str(game_dir),
            "STEAM_COMPAT_LIBRARY_PATHS": str((self.library_dir or root) / "steamapps"),
            "SteamAppId": APP_ID,
            "SteamGameId": APP_ID,
            "WINEDLLOVERRIDES": dll_overrides,
            "WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS": "--disable-gpu --no-sandbox --disable-gpu-compositing",
            "PROTON_USE_XALIA": "0",
        })
        return env

    def prefix_command(self, exe: Path, args: list[str], dll_overrides: str) -> list[str]:
        game_dir, prefix, root = self.require_paths()
        candidates = proton_candidates()
        if candidates:
            _, proton, proton_root = candidates[0]
        elif self.proton and self.proton.exists():
            proton, proton_root = self.proton, root
        else:
            raise RuntimeError("Proton não encontrado.")
        runtime = runtime_path(proton_root) or runtime_path(root)
        command = [str(proton), "run", str(exe), *args]
        if runtime:
            command = [str(runtime), "--", *command]
        return command

    def download(self, url: str, destination: Path, label: str):
        destination.parent.mkdir(parents=True, exist_ok=True)
        temp = destination.with_suffix(destination.suffix + ".part")
        request = urllib.request.Request(url, headers={"User-Agent": "FiveM-on-Linux/1.0"})
        self.log(f"Baixando {label}...")
        try:
            with urllib.request.urlopen(request, timeout=60) as response, open(temp, "wb") as output:
                total = int(response.headers.get("Content-Length", "0") or 0)
                downloaded = 0
                last_report = 0
                while True:
                    block = response.read(1024 * 512)
                    if not block:
                        break
                    output.write(block)
                    downloaded += len(block)
                    if total and downloaded - last_report > max(total // 10, 5 * 1024 * 1024):
                        self.log(f"{label}: {downloaded * 100 // total}%")
                        last_report = downloaded
            if temp.stat().st_size < 1024:
                raise RuntimeError(f"O download de {label} parece incompleto.")
            temp.replace(destination)
            self.log(f"Download concluído: {destination}")
        except Exception:
            if temp.exists():
                temp.unlink()
            raise

    def install_ge_proton(self):
        _, _, root = self.require_paths()
        self.log("Consultando a release mais recente do GE-Proton no GitHub oficial...")
        request = urllib.request.Request(GE_RELEASES_API, headers={"User-Agent": "FiveM-on-Linux/1.0", "Accept": "application/vnd.github+json"})
        with urllib.request.urlopen(request, timeout=40) as response:
            release = json.loads(response.read().decode("utf-8"))
        asset = next((a for a in release.get("assets", []) if a.get("name", "").startswith("GE-Proton") and a.get("name", "").endswith(".tar.gz")), None)
        if not asset:
            raise RuntimeError("Não encontrei o arquivo .tar.gz da release mais recente do GE-Proton.")
        size_gb = asset.get("size", 0) / (1024 ** 3)
        if not self.ask_yes_no("Instalar GE-Proton", f"Será baixada a versão {asset['name']} ({size_gb:.1f} GB, aproximadamente) do GitHub oficial.\n\nDeseja continuar?"):
            self.log("Download do GE-Proton cancelado.")
            return
        archive = CACHE_DIR / asset["name"]
        if not archive.exists() or archive.stat().st_size != asset.get("size", archive.stat().st_size if archive.exists() else -1):
            self.download(asset["browser_download_url"], archive, asset["name"])
        target = root / "compatibilitytools.d"
        target.mkdir(parents=True, exist_ok=True)
        self.log("Extraindo GE-Proton...")
        with tarfile.open(archive, "r:gz") as tar:
            base = target.resolve()
            members = tar.getmembers()
            for member in members:
                destination = (target / member.name).resolve()
                if destination != base and base not in destination.parents:
                    raise RuntimeError("O pacote GE-Proton contém um caminho de extração inválido.")
            tar.extractall(target, members=members)
        installed = next((p for p in target.glob("GE-Proton*/proton") if p.is_file()), None)
        if not installed:
            raise RuntimeError("O arquivo foi extraído, mas o executável proton não foi encontrado.")
        self.log(f"GE-Proton instalado: {installed.parent.name}. Reinicie a Steam para ele aparecer nas opções.")
        self.events.put(("info", f"{installed.parent.name} foi instalado em {target}.\n\nFeche e reabra a Steam; em Propriedades → Compatibilidade, selecione a mesma versão no GTA V Enhanced e no atalho FiveM."))

    def find_existing_shortcut_appid(self) -> int | None:
        if not self.fivem_exe:
            return None
        target = str(self.fivem_exe)
        for root in steam_roots():
            userdata = root / "userdata"
            if not userdata.is_dir():
                continue
            for config in userdata.glob("*/config"):
                shortcuts_file = config / "shortcuts.vdf"
                if not shortcuts_file.is_file():
                    continue
                try:
                    data = parse_binary_vdf(shortcuts_file.read_bytes())
                    for entry in data.get("shortcuts", {}).values():
                        if not isinstance(entry, dict):
                            continue
                        exe = str(get_key(entry, "Exe", "")).strip('"')
                        name = str(get_key(entry, "AppName", ""))
                        if exe == target and name == APP_NAME:
                            value = int(get_key(entry, "appid", 0))
                            return value & 0xFFFFFFFF
                except Exception:
                    continue
        return None

    def find_userdata_config(self) -> Path | None:
        roots = steam_roots()
        options: list[tuple[float, Path]] = []
        for root in roots:
            userdata = root / "userdata"
            if not userdata.is_dir():
                continue
            for user in userdata.iterdir():
                if not user.is_dir() or not user.name.isdigit() or user.name == "0":
                    continue
                config = user / "config"
                if config.is_dir() and ((config / "localconfig.vdf").exists() or (config / "shortcuts.vdf").exists()):
                    mtime = (config / "localconfig.vdf").stat().st_mtime if (config / "localconfig.vdf").exists() else config.stat().st_mtime
                    options.append((mtime, config))
        return max(options, default=(0.0, None), key=lambda item: item[0])[1]

    def register_shortcut(self):
        self.refresh_status()
        if not self.fivem_exe or not self.fivem_exe.is_file():
            messagebox.showinfo("Instale o FiveM primeiro", "Clique em Preparar FiveM e conclua o instalador. Depois volte aqui para registrar o atalho.", parent=self.root)
            return
        if steam_running():
            messagebox.showwarning("Feche a Steam", "A Steam está aberta e pode sobrescrever o arquivo de atalhos ao sair.\n\nFeche a Steam completamente (Steam → Sair) e clique em Registrar atalho Steam novamente.", parent=self.root)
            return
        config_dir = self.find_userdata_config()
        if not config_dir:
            messagebox.showerror("Perfil Steam não encontrado", "Não encontrei userdata/*/config de uma conta Steam. Abra a Steam, entre na sua conta, feche completamente e tente novamente.", parent=self.root)
            return
        path = config_dir / "shortcuts.vdf"
        try:
            data = path.read_bytes() if path.exists() else b""
            root = parse_binary_vdf(data)
        except Exception as exc:
            messagebox.showerror("Atalhos Steam", f"Não consegui ler o arquivo de atalhos:\n{exc}\n\nNenhuma alteração foi feita.", parent=self.root)
            return
        shortcuts = root.setdefault("shortcuts", {})
        name = APP_NAME
        exe_value = f'"{self.fivem_exe}"'
        start_dir = f'"{self.fivem_exe.parent}"'
        options = (
            f'PROTON_USE_XALIA=0 STEAM_COMPAT_DATA_PATH="{self.prefix_base}" '
            'WINEDLLOVERRIDES="wininet=builtin" '
            'WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="--disable-gpu --no-sandbox --disable-gpu-compositing" %command%'
        )
        existing_key = None
        numeric_keys = []
        for key, item in shortcuts.items():
            try:
                numeric_keys.append(int(key))
            except (ValueError, TypeError):
                pass
            if isinstance(item, dict):
                old_exe = str(get_key(item, "Exe", ""))
                old_name = str(get_key(item, "AppName", ""))
                if old_exe.strip('"') == str(self.fivem_exe) or (old_name == name and old_exe.strip('"') == str(self.fivem_exe)):
                    existing_key = key
                    break
        key = str(existing_key if existing_key is not None else (max(numeric_keys, default=-1) + 1))
        appid = signed_appid(exe_value, name)
        entry = {
            "appid": appid,
            "AppName": name,
            "Exe": exe_value,
            "StartDir": start_dir,
            "icon": "",
            "ShortcutPath": "",
            "LaunchOptions": options,
            "IsHidden": 0,
            "AllowDesktopConfig": 1,
            "AllowOverlay": 1,
            "OpenVR": 0,
            "Devkit": 0,
            "DevkitGameID": "",
            "LastPlayTime": 0,
            "FlatpakAppID": "",
            "tags": {"0": "Games", "1": "FiveM"},
        }
        shortcuts[key] = entry
        if path.exists():
            backup = path.with_name(f"shortcuts.vdf.backup-{time.strftime('%Y%m%d-%H%M%S')}")
            shutil.copy2(path, backup)
            self.log(f"Backup criado: {backup}")
        temp = path.with_suffix(".vdf.tmp")
        temp.write_bytes(serialize_binary_vdf(root))
        temp.replace(path)
        self.shortcut_appid = appid if appid >= 0 else appid + 0x100000000
        self.log(f"Atalho registrado em {path}")
        messagebox.showinfo(
            "Atalho criado",
            "O atalho FiveM Enhanced foi registrado na Steam.\n\n"
            "1. Abra a Steam.\n"
            "2. Abra Propriedades do atalho FiveM Enhanced → Compatibilidade.\n"
            "3. Marque a opção para forçar uma ferramenta e selecione a mesma versão Proton/GE-Proton usada pelo GTA V Enhanced.\n\n"
            "O atalho foi criado sem apagar os demais. Não alterei as opções do GTA automaticamente.",
            parent=self.root,
        )
        self.refresh_status()

    def launch_fivem(self):
        if not self.fivem_exe or not self.fivem_exe.is_file():
            messagebox.showinfo("FiveM não instalado", "Primeiro use Preparar FiveM e conclua o instalador.", parent=self.root)
            return
        if self.shortcut_appid is None:
            messagebox.showinfo("Atalho não registrado", "Use Registrar atalho Steam com a Steam completamente fechada; depois reabra a Steam e configure a compatibilidade do atalho.", parent=self.root)
            return
        try:
            subprocess.Popen(["xdg-open", f"steam://rungameid/{self.shortcut_appid}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.log("Enviei o comando para abrir FiveM pela Steam.")
        except Exception as exc:
            messagebox.showerror("Não foi possível abrir", str(exc), parent=self.root)

    def copy_game_options(self):
        self.root.clipboard_clear()
        self.root.clipboard_append(GAME_LAUNCH_OPTIONS)
        self.root.update()
        messagebox.showinfo(
            "Opções copiadas",
            "As opções foram copiadas.\n\nNa Steam: GTA V Enhanced → Propriedades → Geral → Opções de inicialização. Cole a linha copiada e feche a janela.",
            parent=self.root,
        )

    def write_log_file(self, filename: str, content: str):
        try:
            LOG_DIR.mkdir(parents=True, exist_ok=True)
            (LOG_DIR / filename).write_text(content, encoding="utf-8", errors="replace")
        except OSError:
            pass


def main():
    try:
        root = tk.Tk()
        FiveMLinuxApp(root)
        root.mainloop()
    except tk.TclError as exc:
        print(f"Não foi possível abrir a interface gráfica: {exc}", file=__import__("sys").stderr)
        print("Confira se Tkinter está instalado (pacman -S tk) e se a sessão gráfica está ativa.", file=__import__("sys").stderr)
        raise


if __name__ == "__main__":
    main()
