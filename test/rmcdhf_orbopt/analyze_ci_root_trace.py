#!/usr/bin/env python3
"""Match successive CI roots from an ``rscf92.dbg`` dump.

``NEWCOmpi`` writes one CI vector for every requested ASF to ``rscf92.dbg``.
The file has no explicit SCF-cycle marker, but each cycle starts with JALL=1
and then contains the same sequence of JALL values.  This script reconstructs
those cycles, matches roots within each block by maximum absolute vector
overlap, and joins the result with the level-energy rows in
``orbopt_trace.csv``.

The output is diagnostic only.  A low overlap is reported as a flag; it is not
treated as an automatic failure because the first transition can legitimately
move more than later transitions and the debug coefficients are printed with
limited precision.
"""

from __future__ import annotations

import argparse
import csv
import math
import re
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Iterable, Sequence


HEADER_RE = re.compile(r"^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*$")


@dataclass(frozen=True)
class VectorRecord:
    cycle: int
    root: int
    block: int
    ncf: int
    nevecpast: int
    coefficients: tuple[float, ...]


@dataclass(frozen=True)
class LevelEnergy:
    iteration: int
    root: int
    block: int
    position: int
    energy: float
    weight: float | None


def _parse_number(token: str) -> float:
    return float(token.replace("D", "E").replace("d", "e"))


def parse_debug(path: Path) -> list[list[VectorRecord]]:
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    records: list[tuple[int, int, int, int, tuple[float, ...]]] = []
    line_number = 0
    while line_number < len(lines):
        match = HEADER_RE.match(lines[line_number])
        if match is None:
            line_number += 1
            continue

        root, block, ncf, nevecpast = (int(value) for value in match.groups())
        line_number += 1
        while line_number < len(lines) and not lines[line_number].strip():
            line_number += 1
        if (
            line_number >= len(lines)
            or lines[line_number].strip() != "Configuration mixing coefficients:"
        ):
            raise ValueError(
                f"{path}:{line_number + 1}: expected Configuration mixing coefficients"
            )
        line_number += 1

        coefficients: list[float] = []
        while len(coefficients) < ncf:
            if line_number >= len(lines):
                raise ValueError(
                    f"{path}: truncated vector for root {root}, block {block}"
                )
            text = lines[line_number].strip()
            line_number += 1
            if not text:
                continue
            try:
                coefficients.extend(_parse_number(token) for token in text.split())
            except ValueError as exc:
                raise ValueError(
                    f"{path}:{line_number}: invalid CI coefficient line: {text!r}"
                ) from exc
        if len(coefficients) != ncf:
            raise ValueError(
                f"{path}: vector for root {root}, block {block} has too many coefficients"
            )
        records.append((root, block, ncf, nevecpast, tuple(coefficients)))

    if not records:
        raise ValueError(f"{path}: no CI vectors found")

    cycles: list[list[VectorRecord]] = []
    current: list[tuple[int, int, int, int, tuple[float, ...]]] = []
    for record in records:
        root = record[0]
        if root == 1 and current:
            cycles.append(_make_cycle(len(cycles), current, path))
            current = []
        current.append(record)
    if current:
        cycles.append(_make_cycle(len(cycles), current, path))

    first_roots = [record.root for record in cycles[0]]
    for cycle in cycles:
        roots = [record.root for record in cycle]
        if roots != first_roots:
            raise ValueError(
                f"{path}: cycle {cycle[0].cycle} has JALL sequence {roots}, "
                f"expected {first_roots}"
            )
    return cycles


def _make_cycle(
    cycle_number: int,
    records: Sequence[tuple[int, int, int, int, tuple[float, ...]]],
    path: Path,
) -> list[VectorRecord]:
    result = [
        VectorRecord(cycle_number, root, block, ncf, nevecpast, coefficients)
        for root, block, ncf, nevecpast, coefficients in records
    ]
    blocks: dict[int, tuple[int, int]] = {}
    for record in result:
        previous = blocks.setdefault(record.block, (record.ncf, len(record.coefficients)))
        if previous != (record.ncf, len(record.coefficients)):
            raise ValueError(f"{path}: inconsistent NCF in cycle {cycle_number}")
    return result


def parse_level_energies(path: Path) -> dict[tuple[int, int], LevelEnergy]:
    energies: dict[tuple[int, int], LevelEnergy] = {}
    with path.open(newline="", encoding="utf-8") as stream:
        for row in csv.DictReader(stream):
            if row.get("event") != "level_energy":
                continue
            try:
                iteration = int(row["iteration"])
                root = int(row["index"])
                block = int(row["index2"])
                position = int(row["position"])
                # ``level_energy`` is emitted through the candidate-energy
                # field; orbital-update rows use ``energy_old`` instead.
                energy_text = row.get("energy_candidate", "") or row.get("energy_old", "")
                energy = float(energy_text)
            except (KeyError, TypeError, ValueError) as exc:
                raise ValueError(f"{path}: invalid level_energy row: {row}") from exc
            weight_text = row.get("level_weight", "")
            weight = float(weight_text) if weight_text else None
            energies[(iteration, root)] = LevelEnergy(
                iteration, root, block, position, energy, weight
            )
    if not energies:
        raise ValueError(f"{path}: no level_energy rows found")
    return energies


def _norm(vector: Sequence[float]) -> float:
    return math.sqrt(sum(value * value for value in vector))


def cosine_overlap(left: Sequence[float], right: Sequence[float]) -> float:
    left_norm = _norm(left)
    right_norm = _norm(right)
    if left_norm == 0.0 or right_norm == 0.0:
        return 0.0
    return abs(sum(a * b for a, b in zip(left, right, strict=True))) / (
        left_norm * right_norm
    )


def maximum_assignment(matrix: Sequence[Sequence[float]]) -> tuple[float, tuple[int, ...]]:
    """Return the maximum-weight one-to-one assignment for a small block."""

    size = len(matrix)
    if size == 0:
        return 0.0, ()
    if any(len(row) != size for row in matrix):
        raise ValueError("root-overlap matrix is not square")
    if size > 18:
        raise ValueError(
            f"block with {size} roots is too large for the diagnostic assignment solver"
        )

    @lru_cache(maxsize=None)
    def solve(row: int, used: int) -> tuple[float, tuple[int, ...]]:
        if row == size:
            return 0.0, ()
        best_score = -math.inf
        best_assignment: tuple[int, ...] = ()
        for column in range(size):
            if used & (1 << column):
                continue
            tail_score, tail_assignment = solve(row + 1, used | (1 << column))
            score = matrix[row][column] + tail_score
            if score > best_score:
                best_score = score
                best_assignment = (column, *tail_assignment)
        return best_score, best_assignment

    return solve(0, 0)


def dominant_component(vector: Sequence[float]) -> tuple[int, float, float]:
    index, coefficient = max(enumerate(vector, start=1), key=lambda item: abs(item[1]))
    return index, coefficient, coefficient * coefficient


def format_order(
    records: Iterable[VectorRecord], energies: dict[tuple[int, int], LevelEnergy], cycle: int
) -> str:
    block_records = list(records)
    block_records.sort(key=lambda record: energies.get((cycle, record.root), LevelEnergy(0, 0, 0, 0, math.nan, None)).energy)
    return ">".join(str(record.root) for record in block_records)


def global_energy_order(
    energies: dict[tuple[int, int], LevelEnergy], iteration: int
) -> tuple[int, ...]:
    rows = [
        level
        for (level_iteration, _), level in energies.items()
        if level_iteration == iteration
    ]
    rows.sort(key=lambda level: (level.energy, level.root))
    return tuple(level.root for level in rows)


def analyze(
    cycles: Sequence[Sequence[VectorRecord]],
    energies: dict[tuple[int, int], LevelEnergy],
    case_name: str,
    overlap_flag: float,
) -> tuple[list[dict[str, object]], list[dict[str, object]], dict[str, object]]:
    matches: list[dict[str, object]] = []
    summaries: list[dict[str, object]] = []
    permutation_count = 0
    low_overlap_count = 0
    min_overlap = 1.0
    energy_orders: list[dict[str, object]] = []

    previous_order: tuple[int, ...] | None = None
    for iteration in range(len(cycles)):
        for record in cycles[iteration]:
            level = energies.get((iteration, record.root))
            if level is None:
                raise ValueError(
                    f"{case_name}: missing level_energy for cycle {iteration}, root {record.root}"
                )
            if level.block != record.block:
                raise ValueError(
                    f"{case_name}: block mismatch for cycle {iteration}, root {record.root}: "
                    f"rscf92.dbg={record.block}, orbopt_trace={level.block}"
                )
        order = global_energy_order(energies, iteration)
        if len(order) != len(cycles[iteration]):
            raise ValueError(
                f"{case_name}: level_energy count at cycle {iteration} is {len(order)}, "
                f"expected {len(cycles[iteration])}"
            )
        changed = previous_order is not None and order != previous_order
        energy_orders.append(
            {
                "case": case_name,
                "iteration": iteration,
                "root_order": ">".join(str(root) for root in order),
                "order_changed": str(changed).lower(),
            }
        )
        previous_order = order

    for next_cycle in range(1, len(cycles)):
        old_records = cycles[next_cycle - 1]
        new_records = cycles[next_cycle]
        blocks = sorted({record.block for record in old_records})
        if blocks != sorted({record.block for record in new_records}):
            raise ValueError(f"{case_name}: block set changed at cycle {next_cycle}")

        for block in blocks:
            old_block = [record for record in old_records if record.block == block]
            new_block = [record for record in new_records if record.block == block]
            if len(old_block) != len(new_block):
                raise ValueError(
                    f"{case_name}: block {block} root count changed at cycle {next_cycle}"
                )
            matrix = [
                [cosine_overlap(old.coefficients, new.coefficients) for new in new_block]
                for old in old_block
            ]
            assignment_score, assignment = maximum_assignment(matrix)
            diagonal_score = sum(matrix[index][index] for index in range(len(matrix)))
            permutation = any(
                old_block[row].root != new_block[column].root
                for row, column in enumerate(assignment)
            )
            if permutation:
                permutation_count += 1

            old_order = format_order(old_block, energies, next_cycle - 1)
            new_order = format_order(new_block, energies, next_cycle)
            energy_order_changed = old_order != new_order

            block_overlaps = [matrix[row][column] for row, column in enumerate(assignment)]
            block_min_overlap = min(block_overlaps, default=math.nan)
            if math.isfinite(block_min_overlap):
                min_overlap = min(min_overlap, block_min_overlap)
                if block_min_overlap < overlap_flag:
                    low_overlap_count += 1

            summaries.append(
                {
                    "case": case_name,
                    "cycle_previous": next_cycle - 1,
                    "cycle_current": next_cycle,
                    "block": block,
                    "n_roots": len(old_block),
                    "ncf": old_block[0].ncf,
                    "assignment_score": f"{assignment_score:.12g}",
                    "diagonal_score": f"{diagonal_score:.12g}",
                    "min_matched_overlap": f"{block_min_overlap:.12g}",
                    "max_off_diagonal_overlap": f"{max((matrix[i][j] for i in range(len(matrix)) for j in range(len(matrix)) if i != j), default=0.0):.12g}",
                    "permutation": str(permutation).lower(),
                    "energy_order_changed": str(energy_order_changed).lower(),
                    "old_energy_order": old_order,
                    "new_energy_order": new_order,
                    "low_overlap_flag": str(block_min_overlap < overlap_flag).lower(),
                }
            )

            for row, column in enumerate(assignment):
                old = old_block[row]
                new = new_block[column]
                old_component = dominant_component(old.coefficients)
                new_component = dominant_component(new.coefficients)
                old_energy = energies.get((next_cycle - 1, old.root))
                new_energy = energies.get((next_cycle, new.root))
                overlap = matrix[row][column]
                matches.append(
                    {
                        "case": case_name,
                        "cycle_previous": next_cycle - 1,
                        "cycle_current": next_cycle,
                        "block": block,
                        "old_root": old.root,
                        "new_root": new.root,
                        "ncf": old.ncf,
                        "overlap": f"{overlap:.12g}",
                        "diagonal_overlap": f"{matrix[row][row]:.12g}",
                        "matched": "true",
                        "permutation": str(old.root != new.root).lower(),
                        "old_energy": "" if old_energy is None else f"{old_energy.energy:.16e}",
                        "new_energy": "" if new_energy is None else f"{new_energy.energy:.16e}",
                        "old_energy_position": "" if old_energy is None else old_energy.position,
                        "new_energy_position": "" if new_energy is None else new_energy.position,
                        "old_dominant_csf_index": old_component[0],
                        "old_dominant_coefficient": f"{old_component[1]:.12g}",
                        "old_dominant_weight": f"{old_component[2]:.12g}",
                        "new_dominant_csf_index": new_component[0],
                        "new_dominant_coefficient": f"{new_component[1]:.12g}",
                        "new_dominant_weight": f"{new_component[2]:.12g}",
                    }
                )

    metadata = {
        "case": case_name,
        "cycles": len(cycles),
        "roots_per_cycle": len(cycles[0]),
        "blocks": len({record.block for record in cycles[0]}),
        "transitions": len(cycles) - 1,
        "block_transitions": len(summaries),
        "permutation_count": permutation_count,
        "low_overlap_count": low_overlap_count,
        "overlap_flag": overlap_flag,
        "minimum_matched_overlap": min_overlap,
        "energy_orders": energy_orders,
    }
    return matches, summaries, metadata


def write_csv(path: Path, rows: Sequence[dict[str, object]]) -> None:
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def write_report(
    path: Path,
    debug_path: Path,
    trace_path: Path,
    metadata: dict[str, object],
    summaries: Sequence[dict[str, object]],
) -> None:
    flagged = [
        row
        for row in summaries
        if row["permutation"] == "true" or row["low_overlap_flag"] == "true"
    ]
    lines = [
        f"# CI root matching: `{metadata['case']}`",
        "",
        "This is an offline diagnostic from `rscf92.dbg`; it does not rerun RMCDHF and does not change the calculation.",
        "",
        f"- debug: `{debug_path}`",
        f"- orbital trace: `{trace_path}`",
        f"- CI-vector cycles: {metadata['cycles']}",
        f"- roots per cycle: {metadata['roots_per_cycle']}",
        f"- Jπ blocks: {metadata['blocks']}",
        f"- adjacent transitions: {metadata['transitions']}",
        f"- minimum matched overlap: {float(metadata['minimum_matched_overlap']):.6f}",
        f"- diagnostic overlap flag: < {float(metadata['overlap_flag']):.6f}",
        f"- blocks with a low-overlap flag: {metadata['low_overlap_count']}",
        f"- blocks with a non-identity root assignment: {metadata['permutation_count']}",
        "",
        "The dominant CSF columns are indices in the CSF ordering used by the calculation; the debug file does not contain CSF labels.",
        "A low overlap is a review flag, not an automatic failure. The printed debug coefficients are rounded, and the first transition can be larger than later transitions.",
        "",
        "## Flagged transitions",
        "",
    ]
    if not flagged:
        lines.append("No transition crossed the diagnostic overlap threshold or required a non-identity assignment.")
    else:
        lines.extend(
            [
                "| cycle | block | min matched overlap | permutation | energy order changed | old order | new order |",
                "|---:|---:|---:|:---:|:---:|:---|:---|",
            ]
        )
        for row in flagged:
            lines.append(
                f"| {row['cycle_previous']} → {row['cycle_current']} | {row['block']} | {row['min_matched_overlap']} | {row['permutation']} | {row['energy_order_changed']} | {row['old_energy_order']} | {row['new_energy_order']} |"
            )
    changed_orders = [
        row for row in metadata["energy_orders"] if row["order_changed"] == "true"
    ]
    lines.extend(["", "## Global level-energy order", ""])
    lines.append(
        "The root IDs below are JALL indices from `rscf92.dbg`; they are diagnostic indices, not LSJ labels."
    )
    lines.extend(["", "| iteration | root order | changed from previous |", "|---:|:---|:---|"])
    for row in metadata["energy_orders"]:
        lines.append(
            f"| {row['iteration']} | {row['root_order']} | {row['order_changed']} |"
        )
    lines.extend(
        [
            "",
            f"Global level-energy order changes: {len(changed_orders)}.",
        ]
    )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def analyze_case(
    debug_path: Path,
    trace_path: Path,
    output_dir: Path,
    case_name: str,
    overlap_flag: float,
) -> dict[str, object]:
    cycles = parse_debug(debug_path)
    energies = parse_level_energies(trace_path)
    matches, summaries, metadata = analyze(cycles, energies, case_name, overlap_flag)
    output_dir.mkdir(parents=True, exist_ok=True)
    write_csv(output_dir / "ci_root_matches.csv", matches)
    write_csv(output_dir / "ci_root_summary.csv", summaries)
    write_csv(output_dir / "ci_energy_order.csv", metadata["energy_orders"])
    write_report(output_dir / "ci_root_report.md", debug_path, trace_path, metadata, summaries)
    return metadata


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--debug", type=Path, required=True, help="rscf92.dbg path")
    parser.add_argument("--orbopt-trace", type=Path, required=True, help="orbopt_trace.csv path")
    parser.add_argument("--out-dir", type=Path, required=True, help="output directory")
    parser.add_argument("--case", default="case", help="case label in output files")
    parser.add_argument(
        "--overlap-flag",
        type=float,
        default=0.90,
        help="diagnostic-only overlap warning threshold (default: 0.90)",
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if not 0.0 <= args.overlap_flag <= 1.0:
        raise SystemExit("--overlap-flag must be between 0 and 1")
    metadata = analyze_case(
        args.debug,
        args.orbopt_trace,
        args.out_dir,
        args.case,
        args.overlap_flag,
    )
    print(
        f"{metadata['case']}: cycles={metadata['cycles']} "
        f"transitions={metadata['transitions']} "
        f"min_overlap={float(metadata['minimum_matched_overlap']):.6f} "
        f"permutations={metadata['permutation_count']} "
        f"low_overlap_blocks={metadata['low_overlap_count']}"
    )
    print(f"results: {args.out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
