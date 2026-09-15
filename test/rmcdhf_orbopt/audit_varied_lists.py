#!/usr/bin/env python3
"""Offline audit of archived varied lists against actual RCSF orbitals."""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

TOOLS_GUARD = (
    Path(__file__).resolve().parents[3]
    / "graspkit-tools"
    / "scripts"
    / "grasp_regular_cal"
)
sys.path.insert(0, str(TOOLS_GUARD))

from orbopt_stage_guard import orbitals_from_rcsf, selection_decision


CASES = [
    ("Ni I", "Ni_I/e1_vv2/e1_vv2as1.c", "5s,4p,4d", "5s,4p-,4p,4d-,4d"),
    ("Ni/Ca-like", "Ni_Ca-like/even1_cv/e1_cvas1.c", "4s,4p,4d,4f", "4s,4p-,4p,4d-,4d,4f-,4f"),
    ("Cl I", "Cl_I/o1_vv1/o1_vvas1.c", "4s,4p,3d", "4s,4p-,4p,3d-,3d"),
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs_root", type=Path)
    parser.add_argument("--fe-rcsf", type=Path)
    parser.add_argument("--format", choices=("csv", "markdown"), default="csv")
    args = parser.parse_args()
    cases = list(CASES)
    if args.fe_rcsf:
        cases.append(
            (
                "Fe I",
                str(args.fe_rcsf.resolve()),
                "4s,4p,4d,4f",
                "4s,4p-,4p,4d-,4d,4f-,4f",
            )
        )
    rows: list[dict[str, str]] = []
    for case, relative, one_sided, balanced in cases:
        rcsf = Path(relative) if Path(relative).is_absolute() else args.inputs_root / relative
        available = orbitals_from_rcsf(rcsf)
        production = selection_decision(one_sided, available, False)
        diagnostic = selection_decision(one_sided, available, True)
        paired = selection_decision(balanced, available, False)
        rows.append(
            {
                "case": case,
                "one_sided_production": production["decision"],
                "one_sided_diagnostic": diagnostic["decision"],
                "balanced_production": paired["decision"],
                "missing_partners": ";".join(
                    f"{item['orbital']}->{item['missing_partner']}"
                    for item in production["unpaired_orbitals"]
                ),
                "s_orbitals_flagged": str(
                    any(item["orbital"].rstrip("-").endswith("s") for item in production["unpaired_orbitals"])
                ).lower(),
            }
        )
    fields = list(rows[0])
    if args.format == "markdown":
        print("| " + " | ".join(fields) + " |")
        print("|" + "|".join("---" for _ in fields) + "|")
        for row in rows:
            print("| " + " | ".join(row[field] for field in fields) + " |")
    else:
        writer = csv.DictWriter(sys.stdout, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
