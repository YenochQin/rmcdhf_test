#!/usr/bin/env python3
"""Summarize a fixed-damping RMCDHF matrix from result directories."""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

from compare_fine_structure import HARTREE_TO_CM, levels
from compare_rmcdhf import read_trace, summarize


def finite(values: list[float]) -> list[float]:
    return [value for value in values if math.isfinite(value)]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "cases",
        nargs="+",
        metavar="LABEL=RESULT_DIR",
        help="labeled result directory containing orbopt_trace.csv and rmcdhf.sum",
    )
    parser.add_argument("--j-values", default="2,3,4")
    parser.add_argument("--parity", choices=("+", "-"), default="+")
    args = parser.parse_args()

    try:
        j_values = [value.strip() for value in args.j_values.split(",") if value.strip()]
        if len(j_values) < 2 or len(set(j_values)) != len(j_values):
            raise ValueError("--j-values requires at least two unique values")
        print(
            "case,iterations,min_raw_overlap,max_raw_radius_factor,"
            "raw_node_changes,min_accepted_overlap,max_accepted_radius_factor,"
            "accepted_node_changes,fallbacks,ordering,"
            + ",".join(f"J{value}_cm-1" for value in j_values)
        )
        for case in args.cases:
            label, separator, directory_text = case.partition("=")
            if not separator or not label or not directory_text:
                raise ValueError(f"invalid case argument: {case}")
            directory = Path(directory_text)
            iteration_summary = summarize(read_trace(directory / "orbopt_trace.csv"))
            if not iteration_summary:
                raise ValueError(f"{directory}: trace has no orbital metrics")
            rows = list(iteration_summary.values())
            parsed_levels = levels(directory / "rmcdhf.sum")
            energies = {
                j_value: parsed_levels[(1, j_value, args.parity)]
                for j_value in j_values
                if (1, j_value, args.parity) in parsed_levels
            }
            if len(energies) != len(j_values):
                raise ValueError(
                    f"{directory}: expected parity {args.parity} level 1 for "
                    + ",".join(f"J={value}" for value in j_values)
                )
            reference = min(energies.values())
            relative = {
                value: (energy - reference) * HARTREE_TO_CM
                for value, energy in energies.items()
            }
            ordering = "<".join(
                f"J{value}" for value in sorted(energies, key=energies.get)
            )
            raw_overlaps = finite([row["min_overlap"] for row in rows])
            raw_radii = finite([row["max_radius_factor"] for row in rows])
            accepted_overlaps = finite(
                [row["min_accepted_overlap"] for row in rows]
            )
            accepted_radii = finite(
                [row["max_accepted_radius_factor"] for row in rows]
            )
            print(
                f"{label},{max(iteration_summary)},"
                f"{min(raw_overlaps):.8f},{max(raw_radii):.8f},"
                f"{int(sum(row['node_changes'] for row in rows))},"
                f"{min(accepted_overlaps):.8f},{max(accepted_radii):.8f},"
                f"{int(sum(row['accepted_node_changes'] for row in rows))},"
                f"{int(sum(row['fallbacks'] for row in rows))},{ordering},"
                + ",".join(f"{relative[value]:.6f}" for value in j_values)
            )
    except (KeyError, OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
