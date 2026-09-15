#!/usr/bin/env python3
"""Read-only replay of stage gates against archived RMCDHF jobs."""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

TOOLS_GUARD = (
    Path(__file__).resolve().parents[3]
    / "graspkit-tools"
    / "scripts"
    / "grasp_regular_cal"
)
sys.path.insert(0, str(TOOLS_GUARD))

from orbopt_stage_guard import evaluate_candidate


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("results_root", type=Path)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--format", choices=("csv", "markdown"), default="csv")
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8"))
    cases = [
        ("Job 645", "ni-target-baseline-guard-645", config, "accepted"),
        ("Job 643", "round-target-column-ni-643", config, "rejected_convergence"),
        (
            "Job 609",
            "sparse-index-fix-ni-609/as2",
            {**config, "require_strict_convergence": False},
            "rejected_identity",
        ),
    ]
    output: list[dict[str, str]] = []
    failed = False
    for label, relative, case_config, expected in cases:
        path = args.results_root / relative
        result = evaluate_candidate(path, case_config)
        status = "pass" if result.state == expected else "unexpected"
        failed |= status != "pass"
        output.append(
            {
                "job": label,
                "expected": expected,
                "observed": result.state,
                "status": status,
                "reason": "; ".join(result.reasons),
                "coefficient_proxy": (
                    "archived trace: adjacent proxy only; fixed coefficient vectors unavailable"
                ),
            }
        )
    fields = list(output[0])
    if args.format == "markdown":
        print("| " + " | ".join(fields) + " |")
        print("|" + "|".join("---" for _ in fields) + "|")
        for row in output:
            print(
                "| "
                + " | ".join(row[field].replace("|", "\\|") for field in fields)
                + " |"
            )
    else:
        writer = csv.DictWriter(sys.stdout, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(output)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
