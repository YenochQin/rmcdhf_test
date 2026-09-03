#!/usr/bin/env python3
"""Compare rank-independent orbital-guard decisions across result directories."""
from __future__ import annotations

import csv
import sys
from pathlib import Path


def signature(directory: Path) -> tuple[str, tuple[tuple[str, ...], ...], int]:
    exitcode = (directory / "rmcdhf.exitcode").read_text().strip()
    rejected: list[tuple[str, ...]] = []
    accepted_node_changes = 0
    with (directory / "orbopt_trace.csv").open(newline="") as stream:
        for row in csv.DictReader(stream):
            if row["event"] == "rejected":
                rejected.append(
                    (row["iteration"], row["index"], row["np"], row["nh"], row["detail"])
                )
            elif row["event"] == "accepted_metrics":
                accepted_node_changes += row["nodes_old"] != row["nodes_candidate"]
    return exitcode, tuple(rejected), accepted_node_changes


def main() -> int:
    if len(sys.argv) < 3:
        raise SystemExit(f"usage: {sys.argv[0]} LABEL=DIR LABEL=DIR [LABEL=DIR ...]")
    parsed: list[tuple[str, Path]] = []
    for value in sys.argv[1:]:
        label, separator, path = value.partition("=")
        if not separator:
            raise SystemExit(f"invalid result argument: {value}")
        parsed.append((label, Path(path)))
    reference = signature(parsed[0][1])
    print("case,exitcode,rejections,accepted_node_changes,status")
    failed = False
    for label, directory in parsed:
        current = signature(directory)
        status = "match" if current == reference else "different"
        failed |= status != "match"
        print(f"{label},{current[0]},{len(current[1])},{current[2]},{status}")
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
