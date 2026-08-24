#!/usr/bin/env python3
"""Cross-check internal accepted metrics against independent RWFN trends."""

from __future__ import annotations

import argparse
import csv
import math
import sys
from pathlib import Path


def correlation(left: list[float], right: list[float]) -> float:
    left_mean = math.fsum(left) / len(left)
    right_mean = math.fsum(right) / len(right)
    numerator = math.fsum(
        (x - left_mean) * (y - right_mean) for x, y in zip(left, right)
    )
    denominator = math.sqrt(
        math.fsum((x - left_mean) ** 2 for x in left)
        * math.fsum((y - right_mean) ** 2 for y in right)
    )
    return numerator / denominator if denominator else 1.0


def radius_factor(old: str, new: str) -> float:
    left, right = float(old), float(new)
    return max(left / right, right / left)


def crosscheck(trace_path: Path, external_path: Path) -> dict[str, float]:
    with trace_path.open(newline="", encoding="utf-8") as stream:
        trace = list(csv.DictReader(stream))
    selection = {
        int(row["index"]): (int(row["np"]), int(row["nak"]))
        for row in trace
        if row["event"] == "selection"
    }
    accepted: dict[tuple[int, int, int], dict[str, str]] = {}
    for row in trace:
        if row["event"] != "accepted_metrics":
            continue
        n, kappa = selection[int(row["index"])]
        accepted[(int(row["iteration"]), n, kappa)] = row

    with external_path.open(newline="", encoding="utf-8") as stream:
        external = {
            (int(row["iteration"]), int(row["n"]), int(row["kappa"])): row
            for row in csv.DictReader(stream)
        }

    pairs = [(row, external[key]) for key, row in accepted.items() if key in external]
    if len(pairs) < 2:
        raise ValueError("fewer than two matching accepted orbital updates")
    internal_overlap = [abs(float(row["overlap"])) for row, _ in pairs]
    external_overlap = [abs(float(row["overlap"])) for _, row in pairs]
    internal_radius = [
        radius_factor(row["radius_old"], row["radius_candidate"])
        for row, _ in pairs
    ]
    external_radius = [
        radius_factor(row["radius_old"], row["radius_new"]) for _, row in pairs
    ]
    results = {
        "matched_updates": float(len(pairs)),
        "overlap_correlation": correlation(internal_overlap, external_overlap),
        "radius_factor_correlation": correlation(internal_radius, external_radius),
        "max_overlap_abs_difference": max(
            abs(left - right) for left, right in zip(internal_overlap, external_overlap)
        ),
        "max_radius_factor_abs_difference": max(
            abs(left - right) for left, right in zip(internal_radius, external_radius)
        ),
    }
    if results["overlap_correlation"] < 0.8:
        raise ValueError("internal/external overlap trends are inconsistent")
    if results["radius_factor_correlation"] < 0.8:
        raise ValueError("internal/external radius trends are inconsistent")
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    parser.add_argument("external_metrics", type=Path)
    args = parser.parse_args()
    try:
        results = crosscheck(args.trace, args.external_metrics)
    except (OSError, ValueError, KeyError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print("metric,value")
    for name, value in results.items():
        print(f"{name},{value:.16e}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
