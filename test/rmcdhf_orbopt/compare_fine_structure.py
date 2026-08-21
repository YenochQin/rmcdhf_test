#!/usr/bin/env python3
"""Report relative J=2,3,4 level-1 energies from rmcdhf.sum files."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


HARTREE_TO_CM = 219474.6313705
LEVEL_RE = re.compile(
    r"^\s*(\d+)\s+(\d+)\s+([+-])\s+([-+0-9.DEd]+)\s+", re.MULTILINE
)


def levels(path: Path) -> dict[tuple[int, int, str], float]:
    return {
        (int(level), int(j_value), parity): float(energy.replace("D", "E"))
        for level, j_value, parity, energy in LEVEL_RE.findall(
            path.read_text(encoding="utf-8")
        )
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "cases",
        nargs="+",
        metavar="LABEL=RMCDHF.SUM",
        help="labeled result to include in the comparison",
    )
    args = parser.parse_args()

    print("case,ordering,J2_cm-1,J3_cm-1,J4_cm-1")
    try:
        for case in args.cases:
            label, separator, filename = case.partition("=")
            if not separator or not label or not filename:
                raise ValueError(f"invalid case argument: {case}")
            selected = {(1, j, "+"): energy for (level, j, parity), energy in levels(Path(filename)).items() if level == 1 and j in (2, 3, 4) and parity == "+"}
            if len(selected) != 3:
                raise ValueError(f"{filename}: expected positive-parity level 1 for J=2,3,4")
            energies = {j: selected[(1, j, "+")] for j in (2, 3, 4)}
            reference = min(energies.values())
            relative = {j: (energy - reference) * HARTREE_TO_CM for j, energy in energies.items()}
            ordering = "<".join(f"J{j}" for j in sorted(energies, key=energies.get))
            print(
                f"{label},{ordering},{relative[2]:.6f},"
                f"{relative[3]:.6f},{relative[4]:.6f}"
            )
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
