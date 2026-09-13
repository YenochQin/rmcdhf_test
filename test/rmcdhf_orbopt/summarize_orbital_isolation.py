#!/usr/bin/env python3
"""Summarize targeted AS2 orbital-isolation runs without assigning roots."""
from __future__ import annotations
import csv, re, sys
from pathlib import Path

TARGETS = {
    # NIST intervals are expressed relative to the lowest 3F4 level for Ni I.
    # The CSV writer's EnergyLevel zero is run-dependent, so the calculated
    # levels must be shifted to the calculated J=4 level before comparison.
    "ni_i": {"2": 2216.550, "3": 1332.164, "4": 0.0},
    "ni_ca_like": {"2": 0.0, "3": 1880.0, "4": 4070.0},
}

REFERENCE_J = {"ni_i": "4", "ni_ca_like": "2"}

def j_of(label: str) -> str | None:
    # read both plain ``_2`` and the LaTeX emitted by read_level_to_csv,
    # ``_{2}`` (including the trailing math delimiter).
    m = re.search(r"_\{?(\d+(?:/\d+)?)\}?\\?\$?$", label)
    if m:
        return m.group(1)
    m = re.search(r"_\{?(\d+(?:/\d+)?)\}?", label)
    return m.group(1) if m else None

def num(value: str) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None

def summarize_variant(case: str, path: Path) -> dict[str, str]:
    result: dict[str, str] = {"variant": path.name.removeprefix("as2-")}
    target = TARGETS[case]
    exit_file = path / "rmcdhf.exitcode"
    result["rmcdhf_exit"] = exit_file.read_text().strip() if exit_file.exists() else "missing"
    csv_files = list(path.glob("*_rmcdhf.csv"))
    levels: dict[str, float] = {}
    target_totals: dict[str, float] = {}
    if csv_files:
        with csv_files[0].open(newline="", encoding="utf-8") as stream:
            for row in csv.DictReader(stream):
                j = j_of(row.get("LSJ", ""))
                energy = num(row.get("EnergyLevel", ""))
                total = num(row.get("EnergyTotal", ""))
                if j is not None and energy is not None:
                    # The first occurrence of each J is the target 3F term;
                    # later rows reuse J for other LS terms.
                    if j in target and j not in levels:
                        levels[j] = energy
                        if total is not None:
                            target_totals[j] = total
    result["order"] = "<".join(sorted(levels, key=levels.get))
    reference_level = levels.get(REFERENCE_J[case])
    errors = []
    for j, expected in target.items():
        if j in levels:
            calculated = levels[j]
            if reference_level is not None:
                calculated -= reference_level
            errors.append(f"{j}:{calculated-expected:+.2f}")
    result["target_errors_cm-1"] = ";".join(errors)
    trace = path / "orbopt_trace.csv"
    final = None
    low = None
    accepted_nodes = 0
    level_history: dict[int, dict[tuple[str, str], float]] = {}
    if trace.exists():
        with trace.open(newline="", encoding="utf-8") as stream:
            for row in csv.DictReader(stream):
                if row.get("event") == "scf_end":
                    final = row
                if row.get("event") == "level_energy":
                    iteration = int(row.get("iteration", "0"))
                    key = (row.get("index2", ""), row.get("position", ""))
                    energy = num(row.get("energy_candidate", row.get("energy_old", "")))
                    if energy is not None:
                        level_history.setdefault(iteration, {})[key] = energy
                if row.get("event") == "orbital_metrics":
                    overlap = num(row.get("overlap", ""))
                    if overlap is not None and overlap < 0.1 and low is None:
                        low = f"iter={row.get('iteration')},orb={row.get('np','')}" \
                              f"{row.get('nh','')},overlap={overlap:.4g}"
                if row.get("event") == "accepted_metrics":
                    old = row.get("nodes_old", "")
                    new = row.get("nodes_candidate", "")
                    if old and new and old != new:
                        accepted_nodes += 1
    result["first_low_overlap"] = low or ""
    # Map target J values to the trace block/position using the final total
    # energies.  This avoids confusing the many other terms that reuse J.
    target_keys: dict[str, tuple[str, str]] = {}
    if target_totals and level_history:
        final_iteration = max(level_history)
        final_values = level_history[final_iteration]
        for j, total in target_totals.items():
            if final_values:
                key = min(final_values, key=lambda item: abs(final_values[item] - total))
                target_keys[j] = key

    first_crossing = ""
    initial_orders: tuple[str, ...] | None = None
    for iteration in sorted(level_history):
        values = level_history[iteration]
        available = [(j, values[key]) for j, key in target_keys.items() if key in values]
        if len(available) < 2:
            continue
        order = tuple(j for j, _ in sorted(available, key=lambda item: item[1]))
        if initial_orders is None:
            initial_orders = order
        elif order != initial_orders and not first_crossing:
            first_crossing = f"iter={iteration}"
    result["first_energy_order_change"] = first_crossing
    result["accepted_node_changes"] = str(accepted_nodes)
    result["final_iteration"] = final.get("iteration", "") if final else ""
    result["final_detail"] = final.get("detail", "") if final else ""
    result["orbital_converged"] = final.get("convg_orbital", "") if final else ""
    result["energy_converged"] = final.get("convg_energy", "") if final else ""
    result["ci_debug_bytes"] = str((path / "rscf92.dbg").stat().st_size) if (path / "rscf92.dbg").exists() else "0"
    return result

def main() -> int:
    root = Path(sys.argv[1])
    if len(sys.argv) >= 3:
        case = sys.argv[2]
    else:
        case = root.name.split("orbital-isolation-", 1)[-1].rsplit("-", 1)[0]
    if case not in TARGETS:
        raise SystemExit(f"unsupported diagnostic case: {case}")
    rows = [summarize_variant(case, p) for p in sorted(root.glob("as2-*")) if p.is_dir()]
    fields = ["variant", "rmcdhf_exit", "order", "target_errors_cm-1", "first_low_overlap",
              "accepted_node_changes", "first_energy_order_change", "final_iteration", "final_detail", "orbital_converged",
              "energy_converged", "ci_debug_bytes"]
    writer = csv.DictWriter(sys.stdout, fieldnames=fields)
    writer.writeheader()
    writer.writerows(rows)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
