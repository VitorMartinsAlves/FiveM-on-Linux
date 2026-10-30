#!/usr/bin/env python3
"""Regression tests for recognizing a fully staged FiveM Enhanced client."""

import ast
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "app.py"


def load_helpers():
    tree = ast.parse(SOURCE.read_text(encoding="utf-8"))
    wanted = {"profile_for_prefix", "is_fivem_prepared"}
    functions = [
        node for node in tree.body
        if isinstance(node, ast.FunctionDef) and node.name in wanted
    ]
    namespace = {"Path": Path, "os": os}
    exec(compile(ast.Module(body=functions, type_ignores=[]), str(SOURCE), "exec"), namespace)
    return namespace


class FiveMInstallStateTests(unittest.TestCase):
    def setUp(self):
        self.helpers = load_helpers()
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.prefix = Path(self.tmp.name) / "prefix"
        self.user = "testuser"
        self.user_root = self.prefix / "drive_c" / "users" / self.user
        (self.user_root / "AppData/Local/Rockstar Games/Launcher").mkdir(parents=True)
        launcher = self.prefix / "drive_c/FiveM Enhanced"
        launcher.mkdir(parents=True)
        for name in ("FiveM.exe", "modify.exe", "depot-manifest.json", ".depot-build"):
            (launcher / name).write_text("present", encoding="utf-8")
        roaming = self.user_root / "AppData/Roaming/FiveM for GTAV Enhanced"
        roaming.mkdir(parents=True)
        (roaming / "config.toml").write_text('gamePlatform = "rockstar"\n', encoding="utf-8")
        self.products = self.user_root / "AppData/Local/FiveM for GTAV Enhanced/products"
        for product in ("cfxui_gen9", "fivem_gen9"):
            product_root = self.products / product
            (product_root / "123").mkdir(parents=True)
            (product_root / "manifest-123.json").write_text("{}", encoding="utf-8")

    def is_prepared(self):
        with patch.dict(os.environ, {"FIVEM_WINE_USER": self.user}, clear=True):
            return self.helpers["is_fivem_prepared"](self.prefix)

    def test_complete_install_is_recognized(self):
        self.assertTrue(self.is_prepared())

    def test_missing_product_manifest_is_incomplete(self):
        (self.products / "fivem_gen9/manifest-123.json").unlink()
        self.assertFalse(self.is_prepared())

    def test_exe_alone_does_not_count_as_installed(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        prefix = Path(tmp.name) / "prefix"
        exe = prefix / "drive_c/FiveM Enhanced/FiveM.exe"
        exe.parent.mkdir(parents=True)
        exe.touch()
        with patch.dict(os.environ, {"FIVEM_WINE_USER": self.user}, clear=True):
            self.assertFalse(self.helpers["is_fivem_prepared"](prefix))


if __name__ == "__main__":
    unittest.main()
