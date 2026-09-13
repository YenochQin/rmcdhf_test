#!/usr/bin/env python3
"""Compare two fixed-orbital G92RWF files orbital by orbital."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

from compare_rwfn import mean_radius, nodes, norm, overlap, read_rwfn


def label(n: int, kappa: int) -> str:
    letters = "spdfghi"
    if kappa > 0:
        angular = kappa
        suffix = "-"
    else:
        angular = -kappa - 1
        suffix = ""
    if not 0 <= angular < len(letters):
        return f"{n},kappa={kappa}"
    return f"{n}{letters[angular]}{suffix}"


def compare(tf_path: Path, optimized_path: Path, output: Path,
            overlap_limit: float, radius_limit: float) -> int:
    tf = read_rwfn(tf_path)
    optimized = read_rwfn(optimized_path)
    if tf.keys() != optimized.keys():
        missing_tf = sorted(set(optimized) - set(tf))
        missing_optimized = sorted(set(tf) - set(optimized))
        raise ValueError(
            f"orbital sets differ: missing_tf={missing_tf}, "
            f"missing_optimized={missing_optimized}"
        )

    output.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "n", "kappa", "orbital", "overlap", "abs_overlap",
        "norm_tf", "norm_optimized", "radius_tf", "radius_optimized",
        "radius_ratio", "nodes_tf", "nodes_optimized", "node_delta",
        "changed_flag",
    ]
    changed_count = 0
    with output.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for key in sorted(tf):
            old = tf[key]
            new = optimized[key]
            signed_overlap = overlap(old, new)
            old_radius = mean_radius(old)
            new_radius = mean_radius(new)
            radius_ratio = max(old_radius / new_radius, new_radius / old_radius)
            old_nodes = nodes(old)
            new_nodes = nodes(new)
            changed = (
                abs(signed_overlap) < overlap_limit
                or radius_ratio > radius_limit
                or old_nodes != new_nodes
            )
            changed_count += int(changed)
            writer.writerow({
                "n": old.n,
                "kappa": old.kappa,
                "orbital": label(old.n, old.kappa),
                "overlap": f"{signed_overlap:.16e}",
                "abs_overlap": f"{abs(signed_overlap):.16e}",
                "norm_tf": f"{norm(old):.16e}",
                "norm_optimized": f"{norm(new):.16e}",
                "radius_tf": f"{old_radius:.16e}",
                "radius_optimized": f"{new_radius:.16e}",
                "radius_ratio": f"{radius_ratio:.16e}",
                "nodes_tf": old_nodes,
                "nodes_optimized": new_nodes,
                "node_delta": new_nodes - old_nodes,
                "changed_flag": "true" if changed else "false",
            })
    return changed_count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tf", type=Path)
    parser.add_argument("optimized", type=Path)
    parser.add_argument("-o", "--output", required=True, type=Path)
    parser.add_argument("--overlap-limit", type=float, default=0.99)
    parser.add_argument("--radius-limit", type=float, default=1.10)
    args = parser.parse_args()
    if not 0.0 <= args.overlap_limit <= 1.0:
        parser.error("--overlap-limit must be in [0, 1]")
    if args.radius_limit < 1.0:
        parser.error("--radius-limit must be >= 1")
    try:
        changed = compare(
            args.tf,
            args.optimized,
            args.output,
            args.overlap_limit,
            args.radius_limit,
        )
    except (OSError, ValueError, ZeroDivisionError) as error:
        parser.error(str(error))
    print(f"wrote {args.output}; changed_orbitals={changed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
