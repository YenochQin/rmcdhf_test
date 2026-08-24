#!/usr/bin/env bash
# Re-run one prepared MPI case with serial rangular/rmcdhf and compare results.
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <completed-mpi-case-dir> <serial-output-dir>" >&2
    exit 2
fi

mpi_case=$1
output_dir=$2
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
binary_dir=${GRASP_SERIAL_BINDIR:-$repo_root/build-debug/bin}

if [[ -e $output_dir ]]; then
    echo "output directory already exists: $output_dir" >&2
    exit 2
fi
for executable in rangular rmcdhf; do
    if [[ ! -x $binary_dir/$executable ]]; then
        echo "missing executable: $binary_dir/$executable" >&2
        exit 2
    fi
done
for input in isodata rcsf.inp rwfn.inp rangular.stdin rmcdhf.stdin rmcdhf.sum; do
    if [[ ! -f $mpi_case/$input ]]; then
        echo "missing prepared-case file: $mpi_case/$input" >&2
        exit 2
    fi
done

mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)
for input in isodata rcsf.inp rwfn.inp rangular.stdin rmcdhf.stdin; do
    cp "$mpi_case/$input" "$output_dir/$input"
done

cd "$output_dir"
export OMP_NUM_THREADS=${GRASP_OMP_THREADS:-1}
export OPENBLAS_NUM_THREADS=${GRASP_OMP_THREADS:-1}
"$binary_dir/rangular" < rangular.stdin > rangular.stdout 2>&1
"$binary_dir/rmcdhf" < rmcdhf.stdin > rmcdhf.stdout 2>&1
python3 "$repo_root/test/rmcdhf_orbopt/compare_sum.py" \
    "$output_dir/rmcdhf.sum" "$mpi_case/rmcdhf.sum" \
    > "$output_dir/serial_mpi_comparison.csv"
echo "serial comparison complete: $output_dir"
