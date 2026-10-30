#!/usr/bin/env python3
"""Regression tests for rejecting Proton binaries when UMU is not integrated."""

import ast
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "app.py"


def load_detector():
    tree = ast.parse(SOURCE.read_text(encoding="utf-8"))
    function = next(
        node for node in tree.body
        if isinstance(node, ast.FunctionDef) and node.name == "is_proton_runner"
    )
    module = ast.Module(body=[function], type_ignores=[])
    namespace = {"Path": Path}
    exec(compile(module, str(SOURCE), "exec"), namespace)
    return namespace["is_proton_runner"]


class ProtonRunnerPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.detect = staticmethod(load_detector())

    def test_ge_proton_in_lutris_runner_is_rejected(self):
        self.assertTrue(self.detect(Path(
            "/home/vitor/.local/share/lutris/runners/wine/GE-Proton11-7/files/bin/wine"
        )))

    def test_ge_proton_in_steam_compatibility_tools_is_rejected(self):
        self.assertTrue(self.detect(Path(
            "/home/vitor/.steam/compatibilitytools.d/GE-Proton11-7/files/bin/wine"
        )))

    def test_stock_proton_experimental_is_rejected(self):
        self.assertTrue(self.detect(Path(
            "/home/vitor/.local/share/Steam/steamapps/common/Proton - Experimental/files/bin/wine"
        )))

    def test_regular_lutris_wine_is_allowed(self):
        self.assertFalse(self.detect(Path(
            "/home/vitor/.local/share/lutris/runners/wine/lutris-GE-8-26-x86_64/bin/wine"
        )))

    def test_home_directory_named_proton_is_not_a_false_positive(self):
        self.assertFalse(self.detect(Path("/home/proton/Games/wine/bin/wine")))


if __name__ == "__main__":
    unittest.main()
