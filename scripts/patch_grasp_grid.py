#!/usr/bin/env python3
"""Preview, apply, check, or restore radial-grid edits to a GRASP2018 tree.

This patches known source locations, not calculation files or installed binaries.
Unrecognized layouts fail before any source file is written.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal
import difflib
import hashlib
import json
import math
import os
from pathlib import Path
import re
import tempfile


GRID_FILES = (
    "src/appl/rwfnestimate90/getinfo.f90",
    "src/appl/rmcdhf90/getscd.f90",
    "src/appl/rmcdhf90_mpi/getscdmpi.f90",
    "src/appl/rmcdhf90_mem/getscd.f90",
    "src/appl/rmcdhf90_mem_mpi/getscdmpi.f90",
    "src/appl/rci90/getcid.f90",
    "src/appl/rci90_mpi/getcid.f90",
    "src/appl/rbiotransform90/radpar.f90",
    "src/appl/rbiotransform90_mpi/radparmpi.f90",
    "src/appl/rtransition90/getosd.f90",
    "src/appl/rtransition90_phase/getosd.f90",
    "src/appl/rtransition90_mpi/getosdmpi.f90",
    "src/appl/rhfs90/gethfd.f90",
    "src/appl/rhfszeeman95/gethfd.f90",
    "src/appl/sms90/getsmd.f90",
    "src/appl/ris4/getsmd.f90",
    "src/appl/rdensity/getsmd.f90",
    "src/tool/rwfnrotate.f90",
    "src/tool/rwfnrelabel.f90",
)
CAPACITY_FILES = (
    "src/lib/libmod/parameter_def_M.f90",
    "src/appl/rwfnestimate90/frmtfp.f90",
    "src/appl/rwfnestimate90/solvh_I.f90",
    "src/appl/rwfnestimate90/tail_I.f90",
    "src/appl/rwfnestimate90/frmrwf_I.f90",
    "src/appl/rwfnestimate90/summry_I.f90",
)
RESTART_FILES = ("src/appl/rci90/lodres.f90", "src/appl/rci90_mpi/lodres.f90")
CAPACITY_RE = re.compile(r"\b(NNNP|NNN1)\s*=\s*([^)!\n]+)", re.IGNORECASE)


@dataclass(frozen=True)
class Settings:
    nnnp: int | None = None
    n: int | None = None
    h: float | None = None
    rnt_scale: float | None = None
    hp: float | None = None
    accy: float | None = None
    point_n: int | None = None
    point_h: float | None = None
    point_rnt_scale: float | None = None


@dataclass(frozen=True)
class Change:
    relative: str
    before: bytes
    after: bytes


def active(line: str) -> str:
    """Drop Fortran comments for the known assignment/declaration locations."""
    return line.split("!", 1)[0].strip()


def assignment(line: str, name: str) -> bool:
    return re.match(rf"^{name}\s*=", active(line), re.IGNORECASE) is not None


def set_assignment(line: str, name: str, expression: str) -> str:
    code, marker, comment = line.partition("!")
    if ";" in code or "&" in code:
        raise ValueError(f"unsupported continued/multiple assignment: {line.strip()}")
    indent = code[: len(code) - len(code.lstrip())]
    suffix = f" !{comment.rstrip()}" if marker else ""
    return f"{indent}{name} = {expression}{suffix}\n"


def real_literal(value: float) -> str:
    return format(Decimal(str(value)), "E").replace("E", "D")


def validate(settings: Settings, capacity: int) -> None:
    if capacity < 13:
        raise ValueError("NNNP must be at least 13")
    for name in ("n", "point_n"):
        value = getattr(settings, name)
        if value is not None and not 13 <= value <= capacity:
            raise ValueError(f"{name} must be between 13 and NNNP={capacity}")
    for name in ("h", "rnt_scale", "accy", "point_h", "point_rnt_scale", "hp"):
        value = getattr(settings, name)
        if value is not None and (
            not math.isfinite(value) or value < 0 or (name != "hp" and value == 0)
        ):
            raise ValueError(
                f"{name} must be finite and {'nonnegative' if name == 'hp' else 'positive'}"
            )


def patch_capacity(text: str, capacity: int) -> str:
    lines = text.splitlines(keepends=True)
    hits = 0
    for i, line in enumerate(lines):
        if not active(line):
            continue

        def replace(match: re.Match[str]) -> str:
            nonlocal hits
            hits += 1
            name = match[1].upper()
            return f"{name} = {capacity if name == 'NNNP' else capacity + 10}"

        lines[i] = CAPACITY_RE.sub(replace, line)
    if not hits:
        raise ValueError("expected radial capacity declarations are missing")
    return "".join(lines)


def patch_grid(text: str, relative: str, settings: Settings, capacity: int) -> str:
    lines = text.splitlines(keepends=True)
    starts = [i for i, line in enumerate(lines) if assignment(line, "RNT")]
    expected = 1 if "/rci90" in relative else 2
    if len(starts) != expected:
        raise ValueError(
            f"expected {expected} default RNT assignments, found {len(starts)}"
        )
    if expected == 2:
        prefix = [active(line) for line in lines[: starts[0]] if active(line)]
        between = [
            active(line).upper()
            for line in lines[starts[0] : starts[1]]
            if active(line)
        ]
        if (
            not prefix
            or not re.fullmatch(
                r"IF\s*\(NPARM\s*(==|\.EQ\.)\s*0\)\s*THEN", prefix[-1], re.IGNORECASE
            )
            or between[-1] != "ELSE"
        ):
            raise ValueError("unrecognized point/finite nucleus branch layout")
    for position, start in enumerate(starts):
        point = expected == 2 and position == 0
        values = {
            "RNT": settings.point_rnt_scale if point else settings.rnt_scale,
            "H": settings.point_h if point else settings.h,
            "N": settings.point_n if point else settings.n,
        }
        end = (
            starts[position + 1]
            if position + 1 < len(starts)
            else min(start + 12, len(lines))
        )
        for name, value in values.items():
            matches = [i for i in range(start, end) if assignment(lines[i], name)]
            if len(matches) != 1:
                raise ValueError(
                    f"expected one {name} assignment in {'point' if point else 'finite'} branch"
                )
            i = matches[0]
            if value is not None:
                expression = (
                    str(int(value)) if name == "N" else real_literal(float(value))
                )
                if name == "RNT":
                    expression += "/Z"
                lines[i] = set_assignment(lines[i], name, expression)
            if name == "N":
                expression = (
                    active(lines[i]).split("=", 1)[1].strip().upper().replace(" ", "")
                )
                if expression == "NNNP":
                    actual_n = capacity
                elif re.fullmatch(r"MIN\(\d+,NNNP\)", expression):
                    actual_n = min(int(expression[4:].split(",")[0]), capacity)
                elif expression.isdigit():
                    actual_n = int(expression)
                else:
                    raise ValueError(f"unsupported N expression: {expression}")
                if not 13 <= actual_n <= capacity:
                    raise ValueError(
                        f"existing N={actual_n} is incompatible with NNNP={capacity}"
                    )
    hp_lines = [i for i, line in enumerate(lines) if assignment(line, "HP")]
    if len(hp_lines) != 1:
        raise ValueError("expected exactly one common HP assignment")
    if settings.hp is not None:
        i = hp_lines[0]
        lines[i] = set_assignment(lines[i], "HP", real_literal(settings.hp))

    accy_lines = [i for i, line in enumerate(lines) if assignment(line, "ACCY")]
    expected_accy = (1, 2) if "/rmcdhf90" in relative else (1,)
    if len(accy_lines) not in expected_accy:
        raise ValueError("unexpected default ACCY assignments")
    if len(accy_lines) == 2:
        prompts = [
            i for i, line in enumerate(lines) if "Revise the default ACCY" in line
        ]
        if len(prompts) != 1 or accy_lines[1] != prompts[0] - 1:
            raise ValueError("unrecognized additional RMCDHF ACCY assignment")
    i = accy_lines[0]
    if settings.accy is not None:
        lines[i] = set_assignment(lines[i], "ACCY", real_literal(settings.accy))
    # RMCDHF computes ACCY before optional grid input. Recompute before its
    # ACCY prompt, so the user can still override ACCY afterwards.
    if "/rmcdhf90" in relative:
        prompts = [
            i for i, line in enumerate(lines) if "Revise the default ACCY" in line
        ]
        if len(prompts) != 1:
            raise ValueError("expected exactly one RMCDHF ACCY prompt")
        i = prompts[0]
        expression = active(lines[accy_lines[0]]).split("=", 1)[1].strip()
        replacement = set_assignment(lines[accy_lines[0]], "ACCY", expression)
        if assignment(lines[i - 1], "ACCY"):
            lines[i - 1] = replacement
        else:
            lines.insert(i, replacement)
    return "".join(lines)


def initialize_relabel(text: str, reference: str) -> str:
    """Reactivate the old commented grid block using rwfnestimate's defaults."""
    if any(assignment(line, "RNT") for line in text.splitlines()):
        return text
    start = re.search(r"^!\s*IF\s*\(NPARM\b.*$", text, re.MULTILINE | re.IGNORECASE)
    end = re.search(r"^!\s*HP\s*=.*$", text, re.MULTILINE | re.IGNORECASE)
    block = re.search(
        r"^[ \t]*IF \(NPARM == 0\) THEN\n.*?^[ \t]*HP\s*=[^\n]*",
        reference,
        re.MULTILINE | re.DOTALL,
    )
    if not start or not end or not block or end.start() < start.start():
        raise ValueError("unrecognized rwfnrelabel initialization block")
    return text[: start.start()] + block[0].lstrip("\n") + text[end.end() :]


def source_path(root: Path, relative: str) -> Path:
    root = root.resolve()
    path = root / relative
    if path.is_symlink() or not path.resolve().is_relative_to(root):
        raise ValueError(f"source path escapes tree or is a symlink: {relative}")
    if not path.is_file():
        raise ValueError(f"missing required source: {relative}")
    return path


def plan(root: Path, settings: Settings) -> list[Change]:
    required = (*CAPACITY_FILES, *GRID_FILES, *RESTART_FILES)
    originals = {
        relative: source_path(root, relative).read_bytes() for relative in required
    }
    texts = {relative: data.decode("utf-8") for relative, data in originals.items()}
    if any("\r" in text for text in texts.values()):
        raise ValueError(
            "this patcher expects LF source files; convert line endings first"
        )
    capacity_match = re.search(
        r"\bNNNP\s*=\s*(\d+)", texts[CAPACITY_FILES[0]], re.IGNORECASE
    )
    if not capacity_match:
        raise ValueError("cannot read global NNNP")
    capacity = settings.nnnp if settings.nnnp is not None else int(capacity_match[1])
    validate(settings, capacity)
    for relative in CAPACITY_FILES:
        texts[relative] = patch_capacity(texts[relative], capacity)
    reference = texts[GRID_FILES[0]]
    relabel = "src/tool/rwfnrelabel.f90"
    texts[relabel] = initialize_relabel(texts[relabel], reference)
    for relative in GRID_FILES:
        try:
            texts[relative] = patch_grid(texts[relative], relative, settings, capacity)
        except ValueError as error:
            raise ValueError(f"{relative}: {error}") from error
    if settings.accy is not None:
        for relative in RESTART_FILES:
            lines = texts[relative].splitlines(keepends=True)
            indices = [i for i, line in enumerate(lines) if assignment(line, "ACCY")]
            if len(indices) != 1:
                raise ValueError(f"{relative}: expected one restart ACCY assignment")
            i = indices[0]
            lines[i] = set_assignment(lines[i], "ACCY", real_literal(settings.accy))
            texts[relative] = "".join(lines)
    # Inspect the entire tree, not just files we intend to edit. Unknown radial
    # capacity/default locations may be an upstream version we do not support.
    for path in sorted((root / "src").rglob("*.f90")):
        relative = path.relative_to(root).as_posix()
        text = texts.get(relative)
        if text is None:
            text = source_path(root, relative).read_text(encoding="utf-8")
        for number, line in enumerate(text.splitlines(), 1):
            code = active(line)
            for match in CAPACITY_RE.finditer(code):
                expression = match[2].replace(" ", "").upper()
                wanted = capacity if match[1].upper() == "NNNP" else capacity + 10
                if expression != str(wanted) and not (
                    match[1].upper() == "NNN1" and expression == "NNNP+10"
                ):
                    raise ValueError(f"unmatched capacity: {relative}:{number}: {code}")
            if (
                assignment(line, "RNT")
                and relative not in GRID_FILES
                and relative != "src/tool/rwfnmchfmcdf.f90"
            ):
                raise ValueError(f"unrecognized grid initializer: {relative}:{number}")
    return [
        Change(relative, originals[relative], text.encode("utf-8"))
        for relative, text in texts.items()
        if text.encode("utf-8") != originals[relative]
    ]


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def atomic_write(path: Path, data: bytes) -> None:
    mode = path.stat().st_mode & 0o777
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as output:
            temporary = Path(output.name)
            output.write(data)
        temporary.chmod(mode)
        os.replace(temporary, path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def write_changes(root: Path, changes: list[Change]) -> None:
    for change in changes:
        if source_path(root, change.relative).read_bytes() != change.before:
            raise ValueError(f"source changed after preview: {change.relative}")
    written: list[Change] = []
    try:
        for change in changes:
            atomic_write(root / change.relative, change.after)
            written.append(change)
    except Exception:
        for change in reversed(written):
            atomic_write(root / change.relative, change.before)
        raise


def apply(root: Path, changes: list[Change], backup: Path | None) -> Path:
    root = root.resolve()
    if backup is None:
        backup = Path(tempfile.mkdtemp(prefix="grasp-grid-backup-"))
    else:
        backup = backup.resolve()
        if backup.is_relative_to(root / "src"):
            raise ValueError("backup directory must be outside the source directory")
        backup.mkdir(parents=True, exist_ok=False)
    entries = []
    for change in changes:
        saved = backup / change.relative
        saved.parent.mkdir(parents=True, exist_ok=True)
        saved.write_bytes(change.before)
        entries.append(
            {
                "path": change.relative,
                "before": digest(change.before),
                "after": digest(change.after),
            }
        )
    manifest = {
        "root": str(root),
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "files": entries,
    }
    (backup / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Backup: {backup}")
    write_changes(root, changes)
    return backup


def restore_plan(backup: Path, root: Path | None) -> tuple[Path, list[Change]]:
    manifest = json.loads((backup / "manifest.json").read_text(encoding="utf-8"))
    recorded_root = Path(manifest["root"]).resolve()
    if root is not None and root.resolve() != recorded_root:
        raise ValueError("--grasp does not match backup's source tree")
    changes = []
    for entry in manifest["files"]:
        relative = entry["path"]
        path = source_path(recorded_root, relative)
        saved_path = source_path(backup, relative)
        current, saved = path.read_bytes(), saved_path.read_bytes()
        if digest(saved) != entry["before"]:
            raise ValueError(f"backup checksum mismatch: {relative}")
        if digest(current) != entry["after"]:
            raise ValueError(
                f"source has subsequent edits; refusing to overwrite: {relative}"
            )
        changes.append(Change(relative, current, saved))
    return recorded_root, changes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--grasp",
        type=Path,
        help="GRASP2018 source root (default: workspace sibling grasp)",
    )
    parser.add_argument(
        "--nnnp",
        type=int,
        help="compiled capacity; also sets every duplicate NNN1 to NNNP+10",
    )
    parser.add_argument("--n", type=int, help="finite-nucleus runtime point count")
    parser.add_argument(
        "--h", type=float, help="finite-nucleus exponential-coordinate step"
    )
    parser.add_argument(
        "--rnt-scale", type=float, help="finite-nucleus RNT coefficient: RNT=value/Z"
    )
    parser.add_argument(
        "--hp",
        type=float,
        help="common HP for both nuclear models; zero selects exponential grid",
    )
    parser.add_argument(
        "--accy",
        type=float,
        help="explicit grid-related numerical tolerance, including RCI restart",
    )
    parser.add_argument(
        "--point-n",
        type=int,
        help="optional point-nucleus point count; otherwise preserve MIN(220,NNNP)",
    )
    parser.add_argument("--point-h", type=float, help="optional point-nucleus step")
    parser.add_argument(
        "--point-rnt-scale",
        type=float,
        help="optional point-nucleus RNT coefficient: value/Z",
    )
    action = parser.add_mutually_exclusive_group()
    action.add_argument(
        "--apply", action="store_true", help="write edits (default is preview only)"
    )
    action.add_argument(
        "--check",
        action="store_true",
        help="exit 1 if the requested patch is not already applied",
    )
    parser.add_argument("--diff", action="store_true", help="print full unified diffs")
    parser.add_argument(
        "--backup-dir",
        type=Path,
        help="new backup directory for --apply; default is a temporary directory",
    )
    parser.add_argument(
        "--restore",
        type=Path,
        help="preview backup restoration; add --apply to restore",
    )
    args = parser.parse_args()
    settings = Settings(
        **{name: getattr(args, name) for name in Settings.__dataclass_fields__}
    )
    requested = any(value is not None for value in vars(settings).values())
    if args.restore and (requested or args.backup_dir or args.check):
        parser.error(
            "--restore cannot be combined with parameter, backup-dir, or check options"
        )
    if not args.restore and not requested:
        parser.error("provide at least one grid parameter, or --restore")
    if args.backup_dir and not args.apply:
        parser.error("--backup-dir requires --apply")
    try:
        root = args.grasp.resolve() if args.grasp else None
        if args.restore:
            root, changes = restore_plan(args.restore.resolve(), root)
        else:
            root = root or Path(__file__).resolve().parents[2] / "grasp"
            root = root.resolve()
            changes = plan(root, settings)
        print(f"Source: {root}\nFiles requiring changes: {len(changes)}")
        for change in changes:
            print(f"  {change.relative}")
            if args.diff:
                print(
                    "".join(
                        difflib.unified_diff(
                            change.before.decode().splitlines(keepends=True),
                            change.after.decode().splitlines(keepends=True),
                            fromfile=change.relative,
                            tofile=change.relative,
                        )
                    ),
                    end="",
                )
        if args.apply and changes:
            if args.restore:
                write_changes(root, changes)
                print("Restored original sources.")
            else:
                apply(root, changes, args.backup_dir)
                print(
                    "Applied. Rebuild ALL libraries and programs, including MPI, and install them."
                )
        elif not args.apply:
            print(
                "Check only; no files written."
                if args.check
                else "Preview only; add --apply to write."
            )
        if not args.restore:
            print(
                "Scope: GRASP2018 radial applications + rwfnrotate/rwfnrelabel. Unspecified numerical values stay unchanged."
            )
            print(
                "Excluded: independent HF/wfnplot/rwfnmchfmcdf grids; calculation files; old RCI .res grid records; installed binaries."
            )
            print(
                "Runtime input can override defaults. Without --rnt-scale, rwfnrotate retains its historical RNT=2e-6 difference."
            )
        return 1 if args.check and changes else 0
    except (ValueError, OSError, KeyError) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
