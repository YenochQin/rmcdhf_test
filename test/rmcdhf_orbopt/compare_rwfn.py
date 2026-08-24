#!/usr/bin/env python3
"""Compute independent radial metrics from successive G92RWF files."""

from __future__ import annotations

import argparse
import csv
import math
import struct
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Orbital:
    n: int
    kappa: int
    energy: float
    p: tuple[float, ...]
    q: tuple[float, ...]
    r: tuple[float, ...]


def read_record(stream, endian: str) -> bytes | None:
    marker = stream.read(4)
    if not marker:
        return None
    if len(marker) != 4:
        raise ValueError("truncated Fortran record marker")
    (size,) = struct.unpack(f"{endian}i", marker)
    if size < 0 or size > 1_000_000_000:
        raise ValueError(f"invalid Fortran record size {size}")
    payload = stream.read(size)
    trailer = stream.read(4)
    if len(payload) != size or len(trailer) != 4:
        raise ValueError("truncated Fortran record")
    if struct.unpack(f"{endian}i", trailer)[0] != size:
        raise ValueError("mismatched Fortran record markers")
    return payload


def detect_endian(path: Path) -> str:
    marker = path.read_bytes()[:4]
    if len(marker) != 4:
        raise ValueError("empty radial wavefunction file")
    for endian in ("<", ">"):
        if struct.unpack(f"{endian}i", marker)[0] == 6:
            return endian
    raise ValueError("unsupported Fortran record format")


def read_rwfn(path: Path) -> dict[tuple[int, int], Orbital]:
    endian = detect_endian(path)
    orbitals: dict[tuple[int, int], Orbital] = {}
    with path.open("rb") as stream:
        header = read_record(stream, endian)
        if header != b"G92RWF":
            raise ValueError(f"{path}: not a G92RWF file")
        while (metadata := read_record(stream, endian)) is not None:
            if len(metadata) != 20:
                raise ValueError(f"{path}: invalid orbital metadata record")
            n, kappa, energy, points = struct.unpack(f"{endian}iidi", metadata)
            components = read_record(stream, endian)
            grid = read_record(stream, endian)
            if components is None or grid is None:
                raise ValueError(f"{path}: incomplete orbital {n},{kappa}")
            expected_components = 8 * (1 + 2 * points)
            if len(components) != expected_components or len(grid) != 8 * points:
                raise ValueError(f"{path}: invalid array size for orbital {n},{kappa}")
            values = struct.unpack(f"{endian}{1 + 2 * points}d", components)
            radii = struct.unpack(f"{endian}{points}d", grid)
            key = (n, kappa)
            if key in orbitals:
                raise ValueError(f"{path}: duplicate orbital {n},{kappa}")
            orbitals[key] = Orbital(
                n=n,
                kappa=kappa,
                energy=energy,
                p=tuple(values[1 : 1 + points]),
                q=tuple(values[1 + points :]),
                r=tuple(radii),
            )
    return orbitals


def trapezoid(x: tuple[float, ...], y: list[float]) -> float:
    return math.fsum(
        0.5 * (y[index] + y[index - 1]) * (x[index] - x[index - 1])
        for index in range(1, min(len(x), len(y)))
    )


def norm(orbital: Orbital) -> float:
    return trapezoid(orbital.r, [p * p + q * q for p, q in zip(orbital.p, orbital.q)])


def mean_radius(orbital: Orbital) -> float:
    density = [p * p + q * q for p, q in zip(orbital.p, orbital.q)]
    orbital_norm = trapezoid(orbital.r, density)
    return trapezoid(orbital.r, [r * value for r, value in zip(orbital.r, density)]) / orbital_norm


def overlap(old: Orbital, new: Orbital) -> float:
    points = min(len(old.r), len(new.r))
    if old.r[:points] != new.r[:points]:
        raise ValueError(f"radial grids differ for orbital {old.n},{old.kappa}")
    product = [
        old.p[index] * new.p[index] + old.q[index] * new.q[index]
        for index in range(points)
    ]
    raw = trapezoid(old.r[:points], product)
    return raw / math.sqrt(norm(old) * norm(new))


def nodes(orbital: Orbital) -> int:
    maximum = max((abs(value) for value in orbital.p), default=0.0)
    significant = [value for value in orbital.p if abs(value) > maximum * 1.0e-10]
    return sum(left * right < 0.0 for left, right in zip(significant, significant[1:]))


def iteration_from_path(path: Path, fallback: int) -> int:
    marker = ".iter"
    if marker in path.name:
        suffix = path.name.rsplit(marker, 1)[1]
        if suffix.isdigit():
            return int(suffix)
    return fallback


def compare_files(paths: list[Path], writer: csv.writer) -> None:
    previous = read_rwfn(paths[0])
    writer.writerow(
        (
            "iteration",
            "n",
            "kappa",
            "overlap",
            "norm_old",
            "norm_new",
            "radius_old",
            "radius_new",
            "nodes_old",
            "nodes_new",
            "energy_delta",
        )
    )
    for fallback, path in enumerate(paths[1:], start=1):
        current = read_rwfn(path)
        if current.keys() != previous.keys():
            raise ValueError(f"{path}: orbital set differs from preceding file")
        iteration = iteration_from_path(path, fallback)
        for key in sorted(current):
            old, new = previous[key], current[key]
            writer.writerow(
                (
                    iteration,
                    new.n,
                    new.kappa,
                    f"{overlap(old, new):.16e}",
                    f"{norm(old):.16e}",
                    f"{norm(new):.16e}",
                    f"{mean_radius(old):.16e}",
                    f"{mean_radius(new):.16e}",
                    nodes(old),
                    nodes(new),
                    f"{new.energy - old.energy:.16e}",
                )
            )
        previous = current


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rwfn", nargs="+", type=Path, help="initial file followed by iteration snapshots")
    args = parser.parse_args()
    if len(args.rwfn) < 2:
        parser.error("at least two radial wavefunction files are required")
    try:
        compare_files(args.rwfn, csv.writer(sys.stdout, lineterminator="\n"))
    except (OSError, ValueError, ZeroDivisionError, struct.error) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
