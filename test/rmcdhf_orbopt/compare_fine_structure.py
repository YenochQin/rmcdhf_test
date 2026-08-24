#!/usr/bin/env python3
"""Report selected level-1 fine-structure energies from rmcdhf.sum files."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


HARTREE_TO_CM = 219474.6313705
LEVEL_RE = re.compile(
    r"^\s*(\d+)\s+(\d+(?:/\d+)?)\s+([+-])\s+([-+0-9.DEd]+)\s+", re.MULTILINE
)


def levels(path: Path) -> dict[tuple[int, str, str], float]:
    return {
        (int(level), j_value, parity): float(energy.replace("D", "E"))
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
    parser.add_argument("--j-values", default="2,3,4")
    parser.add_argument("--parity", choices=("+", "-"), default="+")
    args = parser.parse_args()

    try:
        j_values = [value.strip() for value in args.j_values.split(",") if value.strip()]
        if len(j_values) < 2 or len(set(j_values)) != len(j_values):
            raise ValueError("--j-values requires at least two unique values")
        print(
            "case,ordering,"
            + ",".join(f"J{value}_cm-1" for value in j_values)
        )
        for case in args.cases:
            label, separator, filename = case.partition("=")
            if not separator or not label or not filename:
                raise ValueError(f"invalid case argument: {case}")
            parsed = levels(Path(filename))
            energies = {
                j: parsed[(1, j, args.parity)]
                for j in j_values
                if (1, j, args.parity) in parsed
            }
            if len(energies) != len(j_values):
                raise ValueError(
                    f"{filename}: expected parity {args.parity} level 1 for "
                    + ",".join(f"J={j}" for j in j_values)
                )
            reference = min(energies.values())
            relative = {j: (energy - reference) * HARTREE_TO_CM for j, energy in energies.items()}
            ordering = "<".join(f"J{j}" for j in sorted(energies, key=energies.get))
            print(
                f"{label},{ordering},"
                + ",".join(f"{relative[j]:.6f}" for j in j_values)
            )
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
