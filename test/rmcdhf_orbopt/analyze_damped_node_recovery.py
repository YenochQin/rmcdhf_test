#!/usr/bin/env python3
"""Compare raw-candidate and post-DAMPOR node changes in an ORBOPT trace."""

from __future__ import annotations

import csv
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} orbopt_trace.csv")
    trace = Path(sys.argv[1])
    pairs: dict[tuple[str, str], dict[str, dict[str, str]]] = {}
    with trace.open(newline="") as stream:
        for row in csv.DictReader(stream):
            event = row["event"]
            if event not in {"orbital_metrics", "accepted_metrics"}:
                continue
            key = (row["iteration"], row["index"])
            pairs.setdefault(key, {})[event] = row

    raw_changes = recovered = remaining = introduced = 0
    print("iteration,index,orbital,raw_node_change,accepted_node_change,recovered")
    for key in sorted(pairs, key=lambda item: (int(item[0]), int(item[1]))):
        events = pairs[key]
        if "orbital_metrics" not in events or "accepted_metrics" not in events:
            continue
        raw = events["orbital_metrics"]
        accepted = events["accepted_metrics"]
        raw_changed = raw["nodes_old"] != raw["nodes_candidate"]
        accepted_changed = accepted["nodes_old"] != accepted["nodes_candidate"]
        raw_changes += raw_changed
        recovered += raw_changed and not accepted_changed
        remaining += raw_changed and accepted_changed
        introduced += not raw_changed and accepted_changed
        if raw_changed or accepted_changed:
            orbital = f'{raw["np"]}{raw["nh"]}'
            print(
                f'{key[0]},{key[1]},{orbital},{str(raw_changed).lower()},'
                f'{str(accepted_changed).lower()},'
                f'{str(raw_changed and not accepted_changed).lower()}'
            )
    print(f"summary,raw_changes,{raw_changes}")
    print(f"summary,recovered_by_damping,{recovered}")
    print(f"summary,remaining_after_damping,{remaining}")
    print(f"summary,introduced_by_damping,{introduced}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
