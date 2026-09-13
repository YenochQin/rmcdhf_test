#!/usr/bin/env python3
"""Aggregate the existing Jobs 631/632 traces and Job 636 decomposition.

The script is deliberately offline: it only reads ``orbopt_trace.csv``, the
already-produced fixed-orbital CSV files, and the CI-root analysis files.  It
does not call GRASP or submit a job.
"""

from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path


HARTREE_CM = 219474.6313705
ENERGY_CHANGE_THRESHOLD_CM = 1.0

CASE_CONFIG = {
    "ni_i": {
        "short": "nii",
        "reference_j": "4",
        "nist": {"2": 2216.550, "3": 1332.164, "4": 0.0},
    },
    "ni_ca_like": {
        "short": "nica",
        "reference_j": "2",
        "nist": {"2": 0.0, "3": 1880.0, "4": 4070.0},
    },
}

J_RE = re.compile(r"_\{(\d+)\}\\?\$?$")


def number(value: str | None) -> float | None:
    if value in (None, ""):
        return None
    try:
        return float(value)
    except ValueError:
        return None


def j_of_lsj(label: str) -> str | None:
    match = J_RE.search(label)
    return match.group(1) if match else None


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def final_levels(path: Path) -> tuple[dict[str, float], dict[str, float]]:
    files = sorted(path.glob("*_rmcdhf.csv"))
    if not files:
        return {}, {}
    levels: dict[str, float] = {}
    totals: dict[str, float] = {}
    for row in read_csv(files[0]):
        label = row.get("LSJ", "")
        if r"\mathrm{F}" not in label or not label.startswith("$^{3}"):
            continue
        j = j_of_lsj(label)
        level = number(row.get("EnergyLevel"))
        total = number(row.get("EnergyTotal"))
        if j in {"2", "3", "4"} and j not in levels and level is not None:
            levels[j] = level
            if total is not None:
                totals[j] = total
    return levels, totals


def trace_levels(path: Path) -> dict[int, dict[tuple[str, str], float]]:
    rows = read_csv(path / "orbopt_trace.csv")
    history: dict[int, dict[tuple[str, str], float]] = {}
    for row in rows:
        if row.get("event") != "level_energy":
            continue
        energy = number(row.get("energy_candidate"))
        if energy is None:
            continue
        iteration = int(row.get("iteration") or 0)
        key = (row.get("index2", ""), row.get("position", ""))
        history.setdefault(iteration, {})[key] = energy
    return history


def target_history(path: Path, case: str) -> dict[int, dict[str, float]]:
    _, totals = final_levels(path)
    history = trace_levels(path)
    if not totals or not history:
        return {}
    final_values = history[max(history)]
    target_keys: dict[str, tuple[str, str]] = {}
    for j, total in totals.items():
        key = min(final_values, key=lambda item: abs(final_values[item] - total))
        if abs(final_values[key] - total) < 1.0e-3:
            target_keys[j] = key
    return {
        iteration: {
            j: values[key]
            for j, key in target_keys.items()
            if key in values
        }
        for iteration, values in history.items()
    }


def intervals(case: str, values: dict[str, float]) -> tuple[float, float] | None:
    config = CASE_CONFIG[case]
    reference = config["reference_j"]
    if not all(j in values for j in ("2", "3", "4")):
        return None
    if case == "ni_i":
        return (
            (values["3"] - values["4"]) * HARTREE_CM,
            (values["2"] - values["4"]) * HARTREE_CM,
        )
    return (
        (values["3"] - values[reference]) * HARTREE_CM,
        (values["4"] - values[reference]) * HARTREE_CM,
    )


def order(values: dict[str, float]) -> str:
    return "<".join(sorted(values, key=values.__getitem__))


def orbital_metrics(path: Path) -> dict[str, str]:
    rows = read_csv(path / "orbopt_trace.csv")
    accepted = [row for row in rows if row.get("event") == "accepted_metrics"]
    metrics = accepted or [row for row in rows if row.get("event") == "orbital_metrics"]
    overlaps = [(number(row.get("overlap")), row) for row in metrics]
    overlaps = [(value, row) for value, row in overlaps if value is not None]
    ratios: list[tuple[float, dict[str, str]]] = []
    for row in metrics:
        old = number(row.get("radius_old"))
        new = number(row.get("radius_candidate"))
        if old not in (None, 0.0) and new not in (None, 0.0):
            ratios.append((new / old, row))
    node_rows = [
        row
        for row in metrics
        if row.get("nodes_old")
        and row.get("nodes_candidate")
        and row["nodes_old"] != row["nodes_candidate"]
    ]
    def orbital(row: dict[str, str]) -> str:
        return f"{row.get('np', '')}{row.get('nh', '')}"

    min_overlap, overlap_row = min(overlaps, default=(None, {}), key=lambda item: item[0])
    max_factor = max(
        (max(abs(ratio), 1.0 / abs(ratio)) for ratio, _ in ratios if ratio),
        default=None,
    )
    first_ratio = ratios[0][0] if ratios else None
    last_ratio = ratios[-1][0] if ratios else None
    fallback_count = sum(
        row.get("event") == "solve_result" and row.get("fallback") == "true"
        for row in rows
    )
    return {
        "orbital": orbital(overlap_row) if overlap_row else "",
        "min_accepted_overlap": "" if min_overlap is None else f"{min_overlap:.6g}",
        "min_overlap_iteration": "" if not overlap_row else overlap_row.get("iteration", ""),
        "first_radius_ratio": "" if first_ratio is None else f"{first_ratio:.6g}",
        "last_radius_ratio": "" if last_ratio is None else f"{last_ratio:.6g}",
        "max_radius_factor": "" if max_factor is None else f"{max_factor:.6g}",
        "accepted_node_changes": str(len(node_rows)),
        "first_node_change_iteration": node_rows[0].get("iteration", "") if node_rows else "",
        "fallbacks": str(fallback_count),
    }


def ci_metrics(path: Path) -> dict[str, str]:
    root_summary = path / "ci_root_analysis" / "ci_root_summary.csv"
    energy_order = path / "ci_root_analysis" / "ci_energy_order.csv"
    summary_rows = read_csv(root_summary) if root_summary.exists() else []
    order_rows = read_csv(energy_order) if energy_order.exists() else []
    matched = [number(row.get("min_matched_overlap")) for row in summary_rows]
    matched = [value for value in matched if value is not None]
    changed = [row for row in order_rows if row.get("order_changed") == "true"]
    return {
        "ci_min_matched_overlap": "" if not matched else f"{min(matched):.6g}",
        "ci_nonidentity_assignment": str(any(row.get("permutation") == "true" for row in summary_rows)).lower(),
        "ci_low_overlap_flag": str(any(row.get("low_overlap_flag") == "true" for row in summary_rows)).lower(),
        "ci_energy_order_changes": str(len(changed)),
        "ci_first_energy_order_change": changed[0].get("iteration", "") if changed else "",
    }


def analyze_variant(case: str, path: Path) -> dict[str, str]:
    config = CASE_CONFIG[case]
    target = target_history(path, case)
    history = sorted(target)
    base_intervals = intervals(case, target[history[0]]) if history else None
    first_interval_change = ""
    first_order_change = ""
    base_order = order(target[history[0]]) if history and len(target[history[0]]) == 3 else ""
    for iteration in history[1:]:
        current = intervals(case, target[iteration])
        if current and base_intervals and not first_interval_change:
            if max(abs(current[i] - base_intervals[i]) for i in (0, 1)) >= ENERGY_CHANGE_THRESHOLD_CM:
                first_interval_change = str(iteration)
        if not first_order_change and len(target[iteration]) == 3 and order(target[iteration]) != base_order:
            first_order_change = str(iteration)
    final_values = target[history[-1]] if history else {}
    final_intervals = intervals(case, final_values)
    nist = config["nist"]
    ref = config["reference_j"]
    errors = (
        (final_intervals[0] - nist["3"], final_intervals[1] - nist["2"])
        if final_intervals and case == "ni_i"
        else (final_intervals[0] - nist["3"], final_intervals[1] - nist["4"])
        if final_intervals
        else None
    )
    result = {
        "case": case,
        "variant": path.name.removeprefix("as2-"),
        "rmcdhf_exit": (path / "rmcdhf.exitcode").read_text().strip() if (path / "rmcdhf.exitcode").exists() else "missing",
        "final_order": order(final_values) if len(final_values) == 3 else "",
        "first_interval_change_iteration": first_interval_change,
        "first_order_change_iteration": first_order_change,
        "interval_1_cm-1": "" if not final_intervals else f"{final_intervals[0]:.2f}",
        "interval_2_cm-1": "" if not final_intervals else f"{final_intervals[1]:.2f}",
        "error_1_cm-1": "" if not errors else f"{errors[0]:+.2f}",
        "error_2_cm-1": "" if not errors else f"{errors[1]:+.2f}",
        "trace_iterations": str(history[-1]) if history else "",
    }
    result.update(orbital_metrics(path))
    result.update(ci_metrics(path))
    return result


FIELDS = [
    "case", "variant", "rmcdhf_exit", "orbital", "first_interval_change_iteration",
    "first_order_change_iteration", "min_accepted_overlap", "min_overlap_iteration",
    "first_radius_ratio", "last_radius_ratio", "max_radius_factor", "accepted_node_changes",
    "first_node_change_iteration", "fallbacks", "final_order", "interval_1_cm-1",
    "interval_2_cm-1", "error_1_cm-1", "error_2_cm-1", "trace_iterations",
    "ci_min_matched_overlap", "ci_nonidentity_assignment", "ci_low_overlap_flag",
    "ci_energy_order_changes", "ci_first_energy_order_change",
]


def write_markdown(path: Path, rows: list[dict[str, str]], decomposition: Path | None) -> None:
    lines = [
        "# AS1/AS2 offline contribution report",
        "",
        "This report reads existing Jobs 631/632 traces and CI-root analyses. No GRASP job is run.",
        "A radius ratio is `radius_candidate / radius_old`; `max_radius_factor` is the symmetric factor >= 1.",
        "",
        "| case | variant | orbital | first interval change | first order change | min overlap | radius first→last | max factor | node changes | final order | interval 1 / 2 (cm⁻¹) | CI order changes | CI nonidentity |",
        "|---|---|---|---:|---:|---:|---:|---:|---:|---|---:|---:|---|",
    ]
    for row in rows:
        lines.append(
            "| {case} | {variant} | {orbital} | {first_interval_change_iteration} | "
            "{first_order_change_iteration} | {min_accepted_overlap} | {first_radius_ratio}→{last_radius_ratio} | "
            "{max_radius_factor} | {accepted_node_changes} | {final_order} | {interval_1_cm-1} / {interval_2_cm-1} | "
            "{ci_energy_order_changes} | {ci_nonidentity_assignment} |".format(**row)
        )
    lines += [
        "",
        "`first interval change` uses a 1 cm⁻¹ threshold against iteration 0. The CI columns are diagnostic: a changed global energy order does not imply a nonidentity vector assignment.",
    ]
    if decomposition and decomposition.exists():
        lines += ["", "## Matched TF/optimized AS2 RCI decomposition", "", "| case | wave | order | interval 1 | interval 2 | error 1 | error 2 |", "|---|---|---|---:|---:|---:|---:|"]
        for row in read_csv(decomposition):
            lines.append("| {case} | {wave} | {order} | {interval_1_cm-1} | {interval_2_cm-1} | {error_1_cm-1} | {error_2_cm-1} |".format(**row))
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--nii", type=Path, required=True)
    parser.add_argument("--nica", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--markdown", type=Path)
    parser.add_argument("--decomposition", type=Path)
    args = parser.parse_args()
    rows: list[dict[str, str]] = []
    for case, root in (("ni_i", args.nii), ("ni_ca_like", args.nica)):
        rows.extend(
            analyze_variant(case, path)
            for path in sorted(root.glob("as2-*"))
            if path.is_dir() and (path / "orbopt_trace.csv").exists()
        )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    if args.markdown:
        args.markdown.parent.mkdir(parents=True, exist_ok=True)
        write_markdown(args.markdown, rows, args.decomposition)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
