#!/usr/bin/env python3
"""Compare every RCI level that has a NIST ASD counterpart, fixed TF vs optimized.

Each LAYER=DIR argument is a same-layer baseline directory written by
``slurm/run_fixed_tf_rci_as<N>_<system>.sbatch``: identical RCI runs on the
fixed-TF wave (``tf/``) and on the optimized r1 wave (``optimized/``).  Level
labels are the jj2lsj leading LSJ components printed by rlevels (``*.level``);
energies are the full-precision RCI eigenvalues from ``*.csum``.

A computed level matches a NIST level when the open-subshell occupations, LS
term, J and parity agree.  NIST levels with an unknown offset (a ``+x``-style
suffix) are compared only within their own offset group, relative to the
lowest matched level of that group; all other levels are compared relative to
the NIST ground level.  ``optimized_no_worse`` applies no tolerance.

Absolute (total) energies are reported for every computed level, whether or
not NIST lists it: optimized minus TF within a layer, and optimized minus the
previous layer's optimized value.  The per-layer summary on stderr weights the
levels as the EOL functional does; it assumes, as in these runs, that RCI
computes exactly the rmcdhf EOL states.
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from dataclasses import dataclass
from itertools import pairwise
from pathlib import Path


HARTREE_TO_CM = 219474.6313705
L_SYMBOLS = "spdfghik"
LEVEL_RE = re.compile(
    r"^\s*(\d+)\s+(\d+)\s+(\d+(?:/\d+)?)\s+([+-])\s+(-?\d+\.\d+)\s+"
    r"(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\S+)\s*$"
)
CSUM_ROW_RE = re.compile(
    r"^\s*(\d+)\s+(\d+(?:/\d+)?)\s+([+-])\s+(-?\d\.\d+D[+-]\d+)\s"
)
GRASP_SUBSHELL_RE = re.compile(r"(\d+)([spdfghik])\((\d+)\)")
NIST_SUBSHELL_RE = re.compile(r"^(\d+)([spdfghik])(\d*)$")
OFFSET_GROUP_RE = re.compile(r"^\+[a-z]$")
WEIGHT_RE = re.compile(r"^\$?([0-9]*\.[0-9]+)")
JOB_RE = re.compile(r"pair-physical-as\d+-[a-z]+(?:-r2)?-(\d+)/")

FIELDS = (
    "system",
    "layer",
    "baseline",
    "r1_job",
    "configuration",
    "term",
    "J",
    "parity",
    "nist_group",
    "reference",
    "status",
    "nist_cm1",
    "tf_cm1",
    "optimized_cm1",
    "tf_error_cm1",
    "optimized_error_cm1",
    "optimized_error_percent",
    "abs_error_change_cm1",
    "optimized_no_worse",
    "tf_total_hartree",
    "optimized_total_hartree",
    "total_change_cm1",
    "optimized_layer_change_cm1",
    "tf_leading_weight",
    "optimized_leading_weight",
)


@dataclass(frozen=True)
class ComputedLevel:
    number: int
    position: int
    j_value: str
    parity: str
    label: str
    energy_hartree: float
    leading_weight: float | None


@dataclass(frozen=True)
class NistLevel:
    configuration: str
    term: str
    j_value: str
    parity: str
    group: str
    level_cm1: float | None


LevelKey = tuple[tuple[tuple[int, int, int], ...], str, str, str]


def open_shell_key(occupations: list[tuple[int, int, int]]) -> tuple[tuple[int, int, int], ...]:
    return tuple(
        sorted((n, l, q) for n, l, q in occupations if q < 2 * (2 * l + 1))
    )


def parity_of(occupations: list[tuple[int, int, int]]) -> str:
    return "+" if sum(l * q for _, l, q in occupations) % 2 == 0 else "-"


def grasp_key(label: str, j_value: str) -> tuple[LevelKey, str]:
    configuration, separator, term = label.rpartition("_")
    if not separator:
        raise ValueError(f"LSJ label has no final term: {label}")
    occupations = [
        (int(n), L_SYMBOLS.index(l), int(q))
        for n, l, q in GRASP_SUBSHELL_RE.findall(configuration)
    ]
    if not occupations:
        raise ValueError(f"LSJ label has no subshells: {label}")
    return (open_shell_key(occupations), term, j_value, parity_of(occupations)), configuration


def unwrap(value: str) -> str:
    value = value.strip()
    if value.startswith('="') and value.endswith('"'):
        value = value[2:-1]
    return value.strip()


def nist_occupations(configuration: str) -> list[tuple[int, int, int]] | None:
    occupations = []
    for token in configuration.split("."):
        if not token or token.startswith("("):
            continue
        match = NIST_SUBSHELL_RE.match(token)
        if match is None:
            return None
        n, l, q = match.groups()
        occupations.append((int(n), L_SYMBOLS.index(l), int(q or 1)))
    return occupations or None


def read_nist(path: Path) -> dict[LevelKey, list[NistLevel]]:
    index: dict[LevelKey, list[NistLevel]] = {}
    with path.open(newline="", encoding="utf-8") as stream:
        for row in csv.DictReader(stream):
            configuration = unwrap(row["Configuration"])
            # Drop the parity mark and any NIST alphabetic term prefix ("a 5D").
            words = unwrap(row["Term"]).rstrip("*").split()
            j_value = unwrap(row["J"])
            occupations = nist_occupations(configuration)
            # Rows without an LS term cannot match an LSJ-labelled level.
            if occupations is None or not j_value or not words or words[-1] == "Limit":
                continue
            term = words[-1]
            text = unwrap(row["Level (cm-1)"]).rstrip("?").strip()
            suffix = unwrap(row.get("Suffix") or "")
            level = NistLevel(
                configuration=configuration,
                term=term,
                j_value=j_value,
                parity=parity_of(occupations),
                group=suffix if OFFSET_GROUP_RE.match(suffix) else "",
                level_cm1=float(text) if text else None,
            )
            key = (open_shell_key(occupations), term, j_value, level.parity)
            index.setdefault(key, []).append(level)
    return index


def only(paths: list[Path], description: str) -> Path:
    if len(paths) != 1:
        raise ValueError(f"expected exactly one {description}, found {len(paths)}")
    return paths[0]


def read_csum(path: Path) -> dict[tuple[int, str, str], float]:
    """Read the absolute eigenvalue table that follows each Eigenenergies line."""

    energies: dict[tuple[int, str, str], float] = {}
    lines = path.read_text(encoding="utf-8").splitlines()
    for start, line in enumerate(lines):
        if line.strip() != "Eigenenergies:":
            continue
        rows_read = 0
        for text in lines[start + 1 :]:
            match = CSUM_ROW_RE.match(text)
            if match:
                position, j_value, parity, energy = match.groups()
                energies[(int(position), j_value, parity)] = float(
                    energy.replace("D", "E")
                )
                rows_read += 1
            elif rows_read and not text.strip():
                break
    if not energies:
        raise ValueError(f"{path}: no eigenvalue tables")
    return energies


def leading_weights(directory: Path) -> dict[int, float]:
    paths = sorted(directory.glob("*_rci.csv"))
    if len(paths) != 1:
        return {}
    weights = {}
    with paths[0].open(newline="", encoding="utf-8") as stream:
        for row in csv.DictReader(stream):
            match = WEIGHT_RE.match(row.get("CompOfAsf", ""))
            if match:
                weights[int(row["No"])] = float(match.group(1))
    return weights


def read_wave_levels(directory: Path) -> list[ComputedLevel]:
    level_path = only(sorted(directory.glob("*.level")), f"{directory}/*.level")
    csum_path = only(sorted(directory.glob("*.csum")), f"{directory}/*.csum")
    energies = read_csum(csum_path)
    weights = leading_weights(directory)
    levels = []
    for line in level_path.read_text(encoding="utf-8").splitlines():
        match = LEVEL_RE.match(line)
        if not match:
            continue
        number, position, j_value, parity, total, _, _, label = match.groups()
        energy = energies.get((int(position), j_value, parity))
        if energy is None:
            raise ValueError(
                f"{csum_path}: no eigenvalue for level {position}, J={j_value}{parity}"
            )
        # The rlevels total is rounded to 1e-7 hartree; anything larger is a
        # position or file mismatch, not rounding.
        if abs(energy - float(total)) > 1.0e-6:
            raise ValueError(
                f"{directory}: level {number} differs between .level and .csum"
            )
        levels.append(
            ComputedLevel(
                number=int(number),
                position=int(position),
                j_value=j_value,
                parity=parity,
                label=label,
                energy_hartree=energy,
                leading_weight=weights.get(int(number)),
            )
        )
    if not levels:
        raise ValueError(f"{level_path}: no levels")
    return levels


def r1_job(baseline: Path) -> str:
    """Return the optimized run whose rcsf.inp the baseline reused."""

    path = baseline / "inputs.sha256"
    if not path.is_file():
        return ""
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.rstrip().endswith("/rcsf.inp"):
            match = JOB_RE.search(line)
            if match:
                return match.group(1)
    return ""


def format_float(value: float | None, digits: int = 6) -> str:
    return "" if value is None else f"{value:.{digits}f}"


def read_layer(baseline: Path) -> tuple[list[ComputedLevel], list[ComputedLevel]]:
    tf_levels = read_wave_levels(baseline / "tf")
    optimized_levels = read_wave_levels(baseline / "optimized")
    if [level.label for level in tf_levels] != [
        level.label for level in optimized_levels
    ] or [(level.j_value, level.parity) for level in tf_levels] != [
        (level.j_value, level.parity) for level in optimized_levels
    ]:
        raise ValueError(f"{baseline}: TF and optimized level labels differ")
    return tf_levels, optimized_levels


def level_identity(level: ComputedLevel) -> tuple[str, str, str]:
    return level.label, level.j_value, level.parity


def eol_weight(j_value: str, weighting: str) -> float:
    """Return the rmcdhf EOL weight: 1 (equal) or 2J+1 (standard)."""

    if weighting == "equal":
        return 1.0
    numerator, _, denominator = j_value.partition("/")
    return 2.0 * int(numerator) / int(denominator or 1) + 1.0


def weighted_mean_change(
    pairs: list[tuple[ComputedLevel, float]], weighting: str
) -> float:
    total_weight = sum(eol_weight(level.j_value, weighting) for level, _ in pairs)
    return (
        sum(eol_weight(level.j_value, weighting) * change for level, change in pairs)
        / total_weight
    )


def compare_layer(
    system: str,
    layer: str,
    baseline: Path,
    levels: tuple[list[ComputedLevel], list[ComputedLevel]],
    previous_totals: dict[tuple[str, str, str], float],
    nist: dict[LevelKey, list[NistLevel]],
) -> list[dict[str, str]]:
    tf_levels, optimized_levels = levels
    matched = []
    for tf_level, optimized_level in zip(tf_levels, optimized_levels):
        key, configuration = grasp_key(tf_level.label, tf_level.j_value)
        if key[3] != tf_level.parity:
            raise ValueError(f"{baseline}: parity of {tf_level.label} disagrees")
        candidates = nist.get(key, [])
        matched.append((tf_level, optimized_level, configuration, key, candidates))

    # One reference per NIST offset group: the ground level for the absolute
    # group, otherwise the lowest matched level of that group.
    references: dict[str, tuple[ComputedLevel, ComputedLevel, NistLevel]] = {}
    for tf_level, optimized_level, _, _, candidates in matched:
        if len(candidates) != 1 or candidates[0].level_cm1 is None:
            continue
        level = candidates[0]
        current = references.get(level.group)
        if current is None or level.level_cm1 < current[2].level_cm1:
            references[level.group] = (tf_level, optimized_level, level)
    absolute = references.get("")
    if absolute is None or absolute[2].level_cm1 != 0.0:
        raise ValueError(f"{baseline}: the NIST ground level was not computed")

    job = r1_job(baseline)
    rows = []
    for tf_level, optimized_level, configuration, key, candidates in matched:
        row = {field: "" for field in FIELDS}
        row.update(
            system=system,
            layer=layer,
            baseline=baseline.name,
            r1_job=job,
            configuration=configuration,
            term=key[1],
            J=tf_level.j_value,
            parity=tf_level.parity,
            tf_total_hartree=format_float(tf_level.energy_hartree, 10),
            optimized_total_hartree=format_float(optimized_level.energy_hartree, 10),
            total_change_cm1=format_float(
                (optimized_level.energy_hartree - tf_level.energy_hartree)
                * HARTREE_TO_CM
            ),
            tf_leading_weight=format_float(tf_level.leading_weight, 3),
            optimized_leading_weight=format_float(optimized_level.leading_weight, 3),
        )
        previous = previous_totals.get(level_identity(optimized_level))
        if previous is not None:
            row["optimized_layer_change_cm1"] = format_float(
                (optimized_level.energy_hartree - previous) * HARTREE_TO_CM
            )
        if not candidates:
            row["status"] = "no_nist_level"
        elif len(candidates) > 1:
            row["status"] = "ambiguous_nist_level"
        elif candidates[0].level_cm1 is None:
            row["status"] = "no_nist_value"
            row["nist_group"] = candidates[0].group
        else:
            level = candidates[0]
            reference_tf, reference_optimized, reference_nist = references[level.group]
            nist_interval = level.level_cm1 - reference_nist.level_cm1
            tf_interval = (
                tf_level.energy_hartree - reference_tf.energy_hartree
            ) * HARTREE_TO_CM
            optimized_interval = (
                optimized_level.energy_hartree - reference_optimized.energy_hartree
            ) * HARTREE_TO_CM
            row.update(
                nist_group=level.group,
                reference=f"{reference_nist.term}{reference_nist.j_value}",
                nist_cm1=format_float(nist_interval, 4),
                tf_cm1=format_float(tf_interval),
                optimized_cm1=format_float(optimized_interval),
            )
            if level is reference_nist:
                row["status"] = "reference"
            else:
                tf_error = tf_interval - nist_interval
                optimized_error = optimized_interval - nist_interval
                change = abs(optimized_error) - abs(tf_error)
                row.update(
                    status="compared",
                    tf_error_cm1=format_float(tf_error),
                    optimized_error_cm1=format_float(optimized_error),
                    optimized_error_percent=format_float(
                        100.0 * optimized_error / nist_interval, 3
                    ),
                    abs_error_change_cm1=format_float(change),
                    optimized_no_worse=str(change <= 0.0),
                )
        rows.append(row)
    return rows


def order_check(rows: list[dict[str, str]], wave: str) -> bool:
    """Return whether the wave orders every offset group exactly like NIST."""

    groups: dict[str, list[tuple[float, float]]] = {}
    for row in rows:
        if row["status"] in {"compared", "reference"}:
            groups.setdefault(row["nist_group"], []).append(
                (float(row["nist_cm1"]), float(row[f"{wave}_cm1"]))
            )
    for values in groups.values():
        computed = [calculated for _, calculated in sorted(values)]
        if any(lower >= upper for lower, upper in pairwise(computed)):
            return False
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("layers", nargs="+", metavar="LAYER=BASELINE_DIR")
    parser.add_argument("--nist", required=True, type=Path)
    parser.add_argument("--system", required=True)
    parser.add_argument(
        "--weights",
        required=True,
        choices=("equal", "standard"),
        help="rmcdhf EOL level weights of the runs (standard: 2J+1)",
    )
    parser.add_argument("--csv", type=Path, help="write the level table here")
    args = parser.parse_args()

    try:
        nist = read_nist(args.nist)
        rows = []
        previous_levels: list[ComputedLevel] = []
        for item in args.layers:
            layer, separator, directory = item.partition("=")
            if not separator or not layer or not directory:
                raise ValueError(f"invalid layer argument: {item}")
            baseline = Path(directory)
            levels = read_layer(baseline)
            previous_totals = {
                level_identity(level): level.energy_hartree for level in previous_levels
            }
            layer_rows = compare_layer(
                args.system, layer, baseline, levels, previous_totals, nist
            )
            for wave in ("tf", "optimized"):
                print(
                    f"{args.system} {layer} {wave}: NIST order "
                    + ("preserved" if order_check(layer_rows, wave) else "BROKEN"),
                    file=sys.stderr,
                )
            tf_levels, optimized_levels = levels
            same_layer = [
                (level, (level.energy_hartree - tf.energy_hartree) * HARTREE_TO_CM)
                for tf, level in zip(tf_levels, optimized_levels)
            ]
            summary = (
                f"{args.system} {layer}: EOL-weighted optimized - TF "
                f"{weighted_mean_change(same_layer, args.weights):+.4f} cm-1, "
                f"lower for {sum(change < 0.0 for _, change in same_layer)}"
                f"/{len(same_layer)} levels"
            )
            across_layers = [
                (level, (level.energy_hartree - previous_totals[level_identity(level)])
                 * HARTREE_TO_CM)
                for level in optimized_levels
                if level_identity(level) in previous_totals
            ]
            if across_layers:
                summary += (
                    "; optimized - previous layer "
                    f"{weighted_mean_change(across_layers, args.weights):+.4f} cm-1, "
                    f"lower for {sum(change < 0.0 for _, change in across_layers)}"
                    f"/{len(across_layers)} levels"
                )
            print(summary, file=sys.stderr)
            rows.extend(layer_rows)
            previous_levels = optimized_levels
    except (OSError, ValueError, KeyError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    output = args.csv.open("w", newline="", encoding="utf-8") if args.csv else sys.stdout
    try:
        writer = csv.DictWriter(output, fieldnames=FIELDS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    finally:
        if args.csv:
            output.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
