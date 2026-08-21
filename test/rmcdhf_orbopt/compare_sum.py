#!/usr/bin/env python3
"""Compare the scientific contents of two rmcdhf.sum files."""

from __future__ import annotations

import argparse
import math
import re
import sys
from pathlib import Path


CSF_RE = re.compile(r"in\s+(\d+)\s+relativistic CSFs")
GRID_RE = re.compile(r"^\s*N\s*=\s*(\d+);", re.MULTILINE)
LEVEL_RE = re.compile(
    r"^\s*(\d+)\s+(\d+)\s+([+-])\s+([-+0-9.DEd]+)\s+", re.MULTILINE
)


def parse(path: Path) -> tuple[int, int, dict[tuple[int, int, str], float]]:
    text = path.read_text(encoding="utf-8")
    csf_match = CSF_RE.search(text)
    grid_match = GRID_RE.search(text)
    levels = {
        (int(level), int(j), parity): float(energy.replace("D", "E"))
        for level, j, parity, energy in LEVEL_RE.findall(text)
    }
    if not csf_match or not grid_match or not levels:
        raise ValueError(f"{path}: missing CSF count, radial grid, or eigenenergies")
    return int(csf_match.group(1)), int(grid_match.group(1)), levels


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("current", type=Path)
    parser.add_argument("reference", type=Path)
    parser.add_argument(
        "--tolerance",
        type=float,
        default=1.0e-9,
        help="absolute eigenenergy tolerance in Hartree (default: 1e-9)",
    )
    parser.add_argument(
        "--allow-energy-differences",
        action="store_true",
        help="report energy differences without treating them as a failure",
    )
    args = parser.parse_args()

    try:
        current_csf, current_grid, current_levels = parse(args.current)
        reference_csf, reference_grid, reference_levels = parse(args.reference)
        if current_csf != reference_csf:
            raise ValueError(f"CSF count differs: {current_csf} vs {reference_csf}")
        if current_levels.keys() != reference_levels.keys():
            raise ValueError("level labels or ordering differ")
        max_delta = 0.0
        max_delta_key: tuple[int, int, str] | None = None
        for key in current_levels:
            left, right = current_levels[key], reference_levels[key]
            delta = abs(left - right)
            if delta > max_delta:
                max_delta = delta
                max_delta_key = key
            if delta > args.tolerance and not args.allow_energy_differences:
                raise ValueError(f"level {key} differs: {left:.16e} vs {right:.16e}")
        if not math.isfinite(max_delta):
            raise ValueError("non-finite energy difference")
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print(f"csfs,{current_csf},{reference_csf},match")
    grid_status = "match" if current_grid == reference_grid else "different"
    print(f"radial_grid_points,{current_grid},{reference_grid},{grid_status}")
    print(f"levels,{len(current_levels)},{len(reference_levels)},match")
    print(f"max_abs_energy_delta_hartree,{max_delta:.16e}")
    if max_delta_key is not None:
        level, j_value, parity = max_delta_key
        print(f"max_delta_level,{level},{j_value},{parity}")
    energy_status = "match" if max_delta <= args.tolerance else "different"
    print(f"energy_status,{energy_status}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
