#!/usr/bin/env python3
"""Summarize and compare rmcdhf_mpi orbital-optimization CSV traces."""

from __future__ import annotations

import argparse
import csv
import math
import sys
from collections import defaultdict
from pathlib import Path


REQUIRED_FIELDS = {
    "event",
    "iteration",
    "index",
    "energy_candidate",
    "fallback",
    "overlap",
    "radius_old",
    "radius_candidate",
    "nodes_old",
    "nodes_candidate",
}


def read_trace(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as stream:
        reader = csv.DictReader(stream)
        missing = REQUIRED_FIELDS.difference(reader.fieldnames or ())
        if missing:
            raise ValueError(f"{path}: missing fields: {', '.join(sorted(missing))}")
        rows = list(reader)
        expected = len(reader.fieldnames or ())
        for line, row in enumerate(rows, start=2):
            if None in row or None in row.values() or len(row) != expected:
                raise ValueError(f"{path}:{line}: inconsistent CSV schema")
    return rows


def number(value: str) -> float | None:
    return float(value) if value else None


def summarize(rows: list[dict[str, str]]) -> dict[int, dict[str, float]]:
    levels: dict[int, dict[int, float]] = defaultdict(dict)
    metrics: dict[int, list[dict[str, str]]] = defaultdict(list)
    accepted_metrics: dict[int, list[dict[str, str]]] = defaultdict(list)
    fallbacks: dict[int, int] = defaultdict(int)

    for row in rows:
        iteration = int(row["iteration"] or 0)
        if row["event"] == "level_energy":
            levels[iteration][int(row["index"])] = float(row["energy_candidate"])
        elif row["event"] == "orbital_metrics":
            metrics[iteration].append(row)
        elif row["event"] == "accepted_metrics":
            accepted_metrics[iteration].append(row)
        elif row["event"] == "solve_result" and row["fallback"] == "true":
            fallbacks[iteration] += 1

    result: dict[int, dict[str, float]] = {}
    for iteration in sorted(set(levels) | set(metrics) | set(accepted_metrics)):
        level_values = [levels[iteration][key] for key in sorted(levels[iteration])]
        delta = level_values[1] - level_values[0] if len(level_values) >= 2 else math.nan
        overlaps = [float(row["overlap"]) for row in metrics[iteration]]
        radius_ratios = [
            max(
                float(row["radius_candidate"]) / float(row["radius_old"]),
                float(row["radius_old"]) / float(row["radius_candidate"]),
            )
            for row in metrics[iteration]
            if number(row["radius_old"]) not in (None, 0.0)
            and number(row["radius_candidate"]) not in (None, 0.0)
        ]
        node_changes = sum(
            row["nodes_old"] != row["nodes_candidate"] for row in metrics[iteration]
        )
        accepted_overlaps = [
            float(row["overlap"]) for row in accepted_metrics[iteration]
        ]
        accepted_radius_factors = [
            max(
                float(row["radius_candidate"]) / float(row["radius_old"]),
                float(row["radius_old"]) / float(row["radius_candidate"]),
            )
            for row in accepted_metrics[iteration]
            if number(row["radius_old"]) not in (None, 0.0)
            and number(row["radius_candidate"]) not in (None, 0.0)
        ]
        accepted_node_changes = sum(
            row["nodes_old"] != row["nodes_candidate"]
            for row in accepted_metrics[iteration]
        )
        result[iteration] = {
            "delta_e": delta,
            "min_overlap": min(overlaps, default=math.nan),
            "max_radius_factor": max(radius_ratios, default=math.nan),
            "node_changes": float(node_changes),
            "fallbacks": float(fallbacks[iteration]),
            "min_accepted_overlap": min(accepted_overlaps, default=math.nan),
            "max_accepted_radius_factor": max(
                accepted_radius_factors, default=math.nan
            ),
            "accepted_node_changes": float(accepted_node_changes),
        }
    return result


def print_summary(path: Path, summary: dict[int, dict[str, float]]) -> None:
    print(f"trace={path}")
    print(
        "iteration,delta_e,min_overlap,max_radius_factor,node_changes,"
        "fallbacks,min_accepted_overlap,max_accepted_radius_factor,"
        "accepted_node_changes"
    )
    for iteration, values in summary.items():
        print(
            f"{iteration},{values['delta_e']:.16e},{values['min_overlap']:.16e},"
            f"{values['max_radius_factor']:.16e},{int(values['node_changes'])},"
            f"{int(values['fallbacks'])},"
            f"{values['min_accepted_overlap']:.16e},"
            f"{values['max_accepted_radius_factor']:.16e},"
            f"{int(values['accepted_node_changes'])}"
        )


def compare(
    current: dict[int, dict[str, float]],
    reference: dict[int, dict[str, float]],
    tolerance: float,
) -> None:
    if current.keys() != reference.keys():
        raise ValueError("trace iterations differ from reference")
    for iteration in current:
        for field in (
            "delta_e",
            "min_overlap",
            "max_radius_factor",
            "min_accepted_overlap",
            "max_accepted_radius_factor",
        ):
            left, right = current[iteration][field], reference[iteration][field]
            if math.isnan(left) and math.isnan(right):
                continue
            scale = max(1.0, abs(left), abs(right))
            if abs(left - right) > tolerance * scale:
                raise ValueError(
                    f"iteration {iteration} {field} differs: {left} vs {right}"
                )
        for field in ("node_changes", "fallbacks", "accepted_node_changes"):
            if current[iteration][field] != reference[iteration][field]:
                raise ValueError(f"iteration {iteration} {field} differs")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    parser.add_argument("--reference", type=Path)
    parser.add_argument("--tolerance", type=float, default=1.0e-10)
    args = parser.parse_args()

    try:
        summary = summarize(read_trace(args.trace))
        print_summary(args.trace, summary)
        if args.reference:
            compare(summary, summarize(read_trace(args.reference)), args.tolerance)
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
