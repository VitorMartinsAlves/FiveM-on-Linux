#!/usr/bin/env python3
"""Write the flat FiveM Enhanced client settings while preserving unrelated TOML."""

from __future__ import annotations

import os
import re
import stat
import sys
import tempfile
from pathlib import Path

ROOT_KEYS = {
    "gamepath": r'gamepath = "R:\\\\"',
    "gamePlatform": 'gamePlatform = "rockstar"',
    "ui_updateChannel": 'ui_updateChannel = "production"',
}
KEY_RE = re.compile(r"^\s*([A-Za-z0-9_-]+)\s*=")
SECTION_RE = re.compile(r"^\s*\[[^\]]+\]")


def update_config(path: Path) -> None:
    original_exists = path.exists()
    text = path.read_text(encoding="utf-8", errors="replace") if original_exists else ""
    lines = text.splitlines()

    first_section = next(
        (i for i, line in enumerate(lines) if SECTION_RE.match(line)),
        len(lines),
    )
    root = lines[:first_section]
    sections = lines[first_section:]

    # Remove only the known client keys from the root scope, then write one
    # canonical value for each. Keys in unrelated TOML tables remain untouched.
    root = [
        line for line in root
        if not (match := KEY_RE.match(line)) or match.group(1) not in ROOT_KEYS
    ]

    # Migrate the previous project's erroneous [gta5enhanced].gamepath entry.
    # Keep every other value and comment in that table.
    filtered_sections: list[str] = []
    current_section = ""
    for line in sections:
        section = re.match(r"^\s*\[([^\]]+)\]", line)
        if section:
            current_section = section.group(1).strip().lower()
            filtered_sections.append(line)
            continue
        match = KEY_RE.match(line)
        if current_section == "gta5enhanced" and match and match.group(1) == "gamepath":
            continue
        filtered_sections.append(line)

    # Place root-scope keys before the first TOML table, as required by TOML.
    while root and not root[-1].strip():
        root.pop()
    if root:
        root.append("")
    root.extend(ROOT_KEYS.values())

    # Remove the now-empty legacy table only if it contains no values or comments.
    cleaned: list[str] = []
    i = 0
    while i < len(filtered_sections):
        section = re.match(r"^\s*\[([^\]]+)\]", filtered_sections[i])
        if section and section.group(1).strip().lower() == "gta5enhanced":
            end = i + 1
            while end < len(filtered_sections) and not SECTION_RE.match(filtered_sections[end]):
                end += 1
            body = filtered_sections[i + 1:end]
            meaningful = [line for line in body if line.strip() and not line.lstrip().startswith("#")]
            if not meaningful:
                i = end
                continue
        cleaned.append(filtered_sections[i])
        i += 1

    output = "\n".join(root + cleaned).rstrip() + "\n"
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = stat.S_IMODE(path.stat().st_mode) if original_exists else 0o600
    fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(output)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary_name, mode)
        os.replace(temporary_name, path)
    finally:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: write-config.py <config.toml>")
    update_config(Path(sys.argv[1]))
