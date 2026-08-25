#!/usr/bin/env python3
"""Compare repeated fixed-damping summaries with the archived reference."""

from __future__ import annotations

import argparse
import csv
import math
import sys
from pathlib import Path


SUMMARY_FILES = (
    "cl_as1_damping.csv",
    "ni_ca_as2_damping.csv",
    "ni_i_as2_damping.csv",
)
DISCRETE_FIELDS = {
    "case",
    "iterations",
    "raw_node_changes",
    "accepted_node_changes",
    "fallbacks",
    "ordering",
}


def read_rows(path: Path) -> tuple[list[str], dict[str, dict[str, str]]]:
    with path.open(newline="", encoding="utf-8") as stream:
        reader = csv.DictReader(stream)
        fields = reader.fieldnames or []
        if "case" not in fields:
            raise ValueError(f"{path}: missing case column")
        rows = {row["case"]: row for row in reader}
    if not rows:
        raise ValueError(f"{path}: no data rows")
    return fields, rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument(
        "repeats",
        nargs="+",
        metavar="LABEL=RESULT_ROOT",
        help="labeled damping-profile output root",
    )
    parser.add_argument("--tolerance", type=float, default=1.0e-6)
    args = parser.parse_args()

    try:
        if args.tolerance < 0.0 or not math.isfinite(args.tolerance):
            raise ValueError("--tolerance must be finite and non-negative")
        print("family,case,repeat,status,max_abs_float_delta")
        for repeat_argument in args.repeats:
            repeat_label, separator, repeat_root_text = repeat_argument.partition("=")
            if not separator or not repeat_label or not repeat_root_text:
                raise ValueError(f"invalid repeat argument: {repeat_argument}")
            repeat_root = Path(repeat_root_text)
            for filename in SUMMARY_FILES:
                reference_fields, reference_rows = read_rows(
                    args.reference / filename
                )
                repeat_fields, repeat_rows = read_rows(repeat_root / filename)
                if repeat_fields != reference_fields:
                    raise ValueError(f"{filename}: CSV fields differ")
                if repeat_rows.keys() != reference_rows.keys():
                    raise ValueError(f"{filename}: damping cases differ")
                family = filename.removesuffix("_damping.csv")
                for case, reference_row in reference_rows.items():
                    repeat_row = repeat_rows[case]
                    max_delta = 0.0
                    for field in reference_fields:
                        left = reference_row[field]
                        right = repeat_row[field]
                        if field in DISCRETE_FIELDS:
                            if left != right:
                                raise ValueError(
                                    f"{filename} {case} {repeat_label}: "
                                    f"{field} differs: {left} vs {right}"
                                )
                            continue
                        delta = abs(float(left) - float(right))
                        max_delta = max(max_delta, delta)
                        if delta > args.tolerance:
                            raise ValueError(
                                f"{filename} {case} {repeat_label}: "
                                f"{field} differs by {delta:.8e}"
                            )
                    print(
                        f"{family},{case},{repeat_label},match,{max_delta:.8e}"
                    )
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
