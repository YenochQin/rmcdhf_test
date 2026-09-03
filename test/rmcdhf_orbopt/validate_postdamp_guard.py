#!/usr/bin/env python3
"""Validate post-damping guard traces without changing calculation results."""
from __future__ import annotations

import csv
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} orbopt_trace.csv")
    path = Path(sys.argv[1])
    rows = list(csv.DictReader(path.open(newline="")))
    events = [row["event"] for row in rows]
    if "control" not in events:
        raise SystemExit("missing ORBOPT control trace")
    accepted = [row for row in rows if row["event"] == "accepted_metrics"]
    node_changes = sum(row["nodes_old"] != row["nodes_candidate"] for row in accepted)
    print(f"trace,{path}")
    print(f"accepted_updates,{len(accepted)}")
    print(f"accepted_node_changes,{node_changes}")
    print("status,pass" if node_changes == 0 else "status,review")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
