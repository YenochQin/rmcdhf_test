"""Offline source-patch checks; no Fortran build or calculation is launched."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "patch_grasp_grid.py"
SPEC = importlib.util.spec_from_file_location("patch_grasp_grid", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
grid = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = grid
SPEC.loader.exec_module(grid)

POINT_AND_FINITE = """      IF (NPARM == 0) THEN
         RNT = EXP((-65.D0/16.D0))/Z
         H = 0.0625D0
         N = MIN(220,NNNP)
      ELSE
         RNT = 2.D-6/Z
         H = 0.05D0
         N = NNNP
      ENDIF
      HP = 0.D0
"""
FINITE = """      RNT = 2.D-6/Z
      H = 0.05D0
      N = NNNP
      HP = 0.D0
"""


def fixture(root: Path) -> None:
    for relative in grid.CAPACITY_FILES:
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            "      integer, parameter :: NNNP = 590\n      integer, parameter :: NNN1 = 600\n"
        )
    for relative in grid.GRID_FILES:
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        block = FINITE if "/rci90" in relative else POINT_AND_FINITE
        if relative.endswith("rwfnrelabel.f90"):
            block = "\n".join("!" + line for line in block.splitlines()) + "\n"
        text = block + "      ACCY = H**6\n"
        if "/rmcdhf90" in relative:
            text += "      IF (NDEF /= 0) THEN\n         WRITE (*,*) 'Revise the default ACCY = ', ACCY\n         READ *, ACCY\n      ENDIF\n"
        text += "      CALL SETQIC\n! NNNP = 590 is a historical comment\n"
        path.write_text(text)
    for relative in grid.RESTART_FILES:
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("      READ (IMCDF) RNT, H, HP\n      ACCY = H**6\n")


class PatchGridTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "grasp"
        fixture(self.root)

    def test_finite_patch_preserves_point_model_and_comments(self) -> None:
        changes = grid.plan(
            self.root, grid.Settings(nnnp=1990, n=1179, h=0.025, rnt_scale=2e-6)
        )
        output = {change.relative: change.after.decode() for change in changes}
        for relative in grid.GRID_FILES:
            self.assertIn("N = 1179", output[relative])
            self.assertIn("H = 2.5D-2", output[relative])
            self.assertIn("! NNNP = 590 is a historical comment", output[relative])
            if "/rci90" not in relative:
                self.assertIn("N = MIN(220,NNNP)", output[relative])
                self.assertIn("H = 0.0625D0", output[relative])
        self.assertTrue(
            all("NNNP = 1990" in output[path] for path in grid.CAPACITY_FILES)
        )
        # Planning is read-only, including on the previously broken helper.
        self.assertIn("!      IF", (self.root / "src/tool/rwfnrelabel.f90").read_text())

    def test_apply_is_idempotent_and_restore_is_byte_exact(self) -> None:
        before = {
            path: (self.root / path).read_bytes()
            for path in (*grid.GRID_FILES, *grid.CAPACITY_FILES, *grid.RESTART_FILES)
        }
        settings = grid.Settings(nnnp=1990, n=1179, h=0.025, accy=1e-10)
        changes = grid.plan(self.root, settings)
        backup = grid.apply(self.root, changes, Path(self.temporary.name) / "backup")
        self.assertEqual(grid.plan(self.root, settings), [])
        # Changing only the grid must preserve a previously selected fixed ACCY.
        reconfigured = grid.plan(self.root, grid.Settings(h=0.02))
        rmcdhf_text = next(
            change.after.decode()
            for change in reconfigured
            if change.relative == "src/appl/rmcdhf90/getscd.f90"
        )
        self.assertEqual(rmcdhf_text.count("ACCY = 1D-10"), 2)
        root, restoration = grid.restore_plan(backup, self.root)
        grid.write_changes(root, restoration)
        for relative, data in before.items():
            self.assertEqual((root / relative).read_bytes(), data)

    def test_unknown_capacity_blocks_all_writes(self) -> None:
        path = self.root / "src/lib/new_grid.f90"
        path.write_text("      integer, parameter :: NNNP = 590\n")
        original = (self.root / grid.CAPACITY_FILES[0]).read_bytes()
        with self.assertRaisesRegex(ValueError, "unmatched capacity"):
            grid.plan(self.root, grid.Settings(nnnp=1990))
        self.assertEqual((self.root / grid.CAPACITY_FILES[0]).read_bytes(), original)

    def test_unknown_initializer_and_malformed_branch_are_rejected(self) -> None:
        path = self.root / "src/lib/new_grid.f90"
        path.write_text("      RNT = 2e-6/Z\n")
        with self.assertRaisesRegex(ValueError, "unrecognized grid initializer"):
            grid.plan(self.root, grid.Settings(h=0.025))
        path.write_text("! no active assignments\n")
        current = self.root / grid.GRID_FILES[0]
        current.write_text(current.read_text().replace("H = 0.05D0", "HH = 0.05D0"))
        with self.assertRaisesRegex(ValueError, "expected one H assignment"):
            grid.plan(self.root, grid.Settings(h=0.025))

    def test_invalid_numbers_and_runtime_capacity_conflict(self) -> None:
        for settings in (
            grid.Settings(nnnp=10),
            grid.Settings(nnnp=590, n=591),
            grid.Settings(h=float("nan")),
            grid.Settings(h=-0.01),
            grid.Settings(hp=-1),
            grid.Settings(accy=0),
        ):
            with self.subTest(settings=settings), self.assertRaises(ValueError):
                grid.plan(self.root, settings)
        path = self.root / grid.GRID_FILES[0]
        path.write_text(path.read_text().replace("N = NNNP", "N = 1990"))
        with self.assertRaisesRegex(ValueError, "incompatible"):
            grid.plan(self.root, grid.Settings(nnnp=590))

    def test_point_model_and_common_hp_can_be_selected_explicitly(self) -> None:
        changes = grid.plan(
            self.root,
            grid.Settings(
                nnnp=1990, point_n=400, point_h=0.03, point_rnt_scale=0.01, hp=0.1
            ),
        )
        text = next(
            change.after.decode()
            for change in changes
            if change.relative == grid.GRID_FILES[0]
        )
        self.assertIn("N = 400", text)
        self.assertIn("H = 0.05D0", text)  # finite model unchanged
        self.assertIn("HP = 1D-1", text)

    def test_restore_refuses_subsequent_source_edits(self) -> None:
        changes = grid.plan(self.root, grid.Settings(nnnp=1990))
        backup = grid.apply(self.root, changes, Path(self.temporary.name) / "backup")
        path = self.root / changes[0].relative
        path.write_bytes(path.read_bytes() + b"! user's later edit\n")
        with self.assertRaisesRegex(ValueError, "subsequent edits"):
            grid.restore_plan(backup, self.root)
        self.assertTrue(path.read_bytes().endswith(b"! user's later edit\n"))

    def test_restore_refuses_corrupted_backup(self) -> None:
        changes = grid.plan(self.root, grid.Settings(nnnp=1990))
        backup = grid.apply(self.root, changes, Path(self.temporary.name) / "backup")
        saved = backup / changes[0].relative
        saved.write_bytes(saved.read_bytes() + b"! corrupted backup\n")
        with self.assertRaisesRegex(ValueError, "backup checksum mismatch"):
            grid.restore_plan(backup, self.root)

    def test_write_failure_rolls_back_completed_files(self) -> None:
        changes = grid.plan(self.root, grid.Settings(nnnp=1990))
        original_write = grid.atomic_write
        calls = 0

        def failing_write(path: Path, data: bytes) -> None:
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError("simulated disk failure")
            original_write(path, data)

        with patch.object(grid, "atomic_write", side_effect=failing_write):
            with self.assertRaisesRegex(OSError, "simulated disk failure"):
                grid.write_changes(self.root, changes)
        for change in changes:
            self.assertEqual((self.root / change.relative).read_bytes(), change.before)


if __name__ == "__main__":
    unittest.main()
