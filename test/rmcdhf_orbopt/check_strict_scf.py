#!/usr/bin/env python3
"""Validate legacy or strict SCF stopping semantics in an orbital trace."""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path


REQUIRED_FIELDS = {
    "event",
    "iteration",
    "convg_orbital",
    "convg_energy",
    "convg_final",
    "convg_legacy",
    "convg_strict",
    "strict_streak",
    "energy_valid",
}


def read_scf_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as stream:
        reader = csv.DictReader(stream)
        missing = REQUIRED_FIELDS.difference(reader.fieldnames or ())
        if missing:
            raise ValueError(f"missing fields: {', '.join(sorted(missing))}")
        rows = [row for row in reader if row["event"] == "scf_end"]
    if not rows:
        raise ValueError("trace contains no scf_end events")
    return rows


def flag(row: dict[str, str], name: str) -> bool:
    value = row[name]
    if value not in {"true", "false"}:
        raise ValueError(f"iteration {row['iteration']}: invalid {name}={value!r}")
    return value == "true"


def validate(rows: list[dict[str, str]], mode: str) -> None:
    first = rows[0]
    if flag(first, "energy_valid"):
        raise ValueError("the first SCF iteration must not have a prior energy")

    final_rows = [row for row in rows if flag(row, "convg_final")]
    if len(final_rows) != 1 or final_rows[0] is not rows[-1]:
        raise ValueError("exactly the last scf_end row must be final")

    for row in rows:
        orbital = flag(row, "convg_orbital")
        energy = flag(row, "convg_energy")
        energy_valid = flag(row, "energy_valid")
        if flag(row, "convg_legacy") != (orbital or energy):
            raise ValueError(f"iteration {row['iteration']}: invalid legacy value")
        if flag(row, "convg_strict") != (orbital and energy and energy_valid):
            raise ValueError(f"iteration {row['iteration']}: invalid strict value")

    final = rows[-1]
    if mode == "legacy":
        if not flag(final, "convg_legacy"):
            raise ValueError("legacy run did not stop on its legacy criterion")
    else:
        if int(final["strict_streak"]) < 2:
            raise ValueError("strict run stopped before two consecutive passes")
        if len(rows) < 2 or not all(
            flag(row, "convg_strict") for row in rows[-2:]
        ):
            raise ValueError("the last two strict criteria are not both true")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    parser.add_argument("--mode", choices=("legacy", "strict"), required=True)
    args = parser.parse_args()
    try:
        rows = read_scf_rows(args.trace)
        validate(rows, args.mode)
    except (OSError, ValueError) as error:
        print(f"error: {args.trace}: {error}", file=sys.stderr)
        return 1
    print(
        f"valid {args.mode} convergence: iterations={len(rows)} "
        f"final_iteration={rows[-1]['iteration']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
