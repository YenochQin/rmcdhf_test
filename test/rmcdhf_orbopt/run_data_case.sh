#!/usr/bin/env bash
# Run one AS1/AS2 regression from test/data without modifying archived data.
set -euo pipefail

if [[ $# -lt 3 || $# -gt 6 ]]; then
    echo "usage: $0 <ni_i|ni_ca_like> <optimized|nv|minus_only|balanced> <output-dir> [nprocs] [estimate|archived] [stage]" >&2
    exit 2
fi

case_name=$1
mode=$2
output_dir=$3
nprocs=${4:-4}
initial_wave=${5:-estimate}
stage=${6:-1}

if ! [[ $nprocs =~ ^[1-9][0-9]*$ ]]; then
    echo "nprocs must be a positive integer" >&2
    exit 2
fi
if [[ -e $output_dir ]]; then
    echo "output directory already exists: $output_dir" >&2
    exit 2
fi
if [[ $initial_wave != estimate && $initial_wave != archived ]]; then
    echo "initial wave must be 'estimate' or 'archived'" >&2
    exit 2
fi
if [[ $stage != 1 && $stage != 2 ]]; then
    echo "stage must be 1 or 2" >&2
    exit 2
fi

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
binary_dir=${GRASP_BINDIR:-$repo_root/build-debug/bin}
data_root=$repo_root/test/data

case "$case_name:$mode" in
    ni_i:optimized)
        source_dir=$data_root/Ni_I/e1_vv2
        prefix=e1_vv2
        varied_as1='5s,4p,4d'
        varied_as2='6s,5p,5d,4f'
        level_weight=1
        ;;
    ni_i:nv)
        source_dir=$data_root/Ni_I/e1_vv2_NV
        prefix=e1_vv2_NV
        varied_as1=''
        varied_as2=''
        level_weight=1
        ;;
    ni_i:minus_only)
        source_dir=$data_root/Ni_I/e1_vv2
        prefix=e1_vv2
        varied_as1='5s,4p-,4d-'
        varied_as2='6s,5p-,5d-,4f-'
        level_weight=1
        ;;
    ni_i:balanced)
        source_dir=$data_root/Ni_I/e1_vv2
        prefix=e1_vv2
        varied_as1='5s,4p-,4p,4d-,4d'
        varied_as2='6s,5p-,5p,5d-,5d,4f-,4f'
        level_weight=1
        ;;
    ni_ca_like:optimized)
        source_dir=$data_root/Ni_Ca-like/even1_cv
        prefix=e1_cv
        varied_as1='4s,4p,4d,4f'
        varied_as2='5s,5p,5d,5f,5g'
        level_weight=5
        ;;
    ni_ca_like:nv)
        source_dir=$data_root/Ni_Ca-like/e1_cv_NV
        prefix=e1_cv_NV
        varied_as1=''
        varied_as2=''
        level_weight=5
        ;;
    ni_ca_like:minus_only)
        source_dir=$data_root/Ni_Ca-like/even1_cv
        prefix=e1_cv
        varied_as1='4s,4p-,4d-,4f-'
        varied_as2='5s,5p-,5d-,5f-,5g-'
        level_weight=5
        ;;
    ni_ca_like:balanced)
        source_dir=$data_root/Ni_Ca-like/even1_cv
        prefix=e1_cv
        varied_as1='4s,4p-,4p,4d-,4d,4f-,4f'
        varied_as2='5s,5p-,5p,5d-,5d,5f-,5f,5g-,5g'
        level_weight=5
        ;;
    *)
        echo "unsupported case/mode: $case_name $mode" >&2
        exit 2
        ;;
esac

rcsf_name=${prefix}as${stage}.c
wave_name=${prefix}as$((stage - 1)).w
archived_sum=${prefix}as${stage}.sum
archived_wave=${prefix}as${stage}.w
if [[ $stage == 1 ]]; then
    varied=$varied_as1
else
    varied=$varied_as2
fi

for executable in rangular_mpi rwfnestimate rmcdhf_mpi; do
    if [[ ! -x $binary_dir/$executable ]]; then
        echo "missing executable: $binary_dir/$executable" >&2
        exit 2
    fi
done

mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)
mpi_tmp=$output_dir/mpi_tmp
mkdir "$mpi_tmp"

cp "$source_dir/isodata" "$output_dir/isodata"
cp "$source_dir/$rcsf_name" "$output_dir/rcsf.inp"
cp "$source_dir/$wave_name" "$output_dir/previous.w"
cp "$source_dir/$archived_sum" "$output_dir/archived.sum"
if [[ $initial_wave == archived ]]; then
    cp "$source_dir/$archived_wave" "$output_dir/rwfn.inp"
fi

source /usr/share/Modules/init/bash
module load mpi/openmpi-x86_64
export MPI_TMP=$mpi_tmp
export GRASP_TRACE_ORBOPT=1
# FlexiBLAS uses the OpenBLAS OpenMP backend on the reference host. Keep
# each MPI rank single-threaded to avoid rank_count x core_count oversubscription.
export OMP_NUM_THREADS=${GRASP_OMP_THREADS:-1}
export OPENBLAS_NUM_THREADS=${GRASP_OMP_THREADS:-1}
if [[ $mode == balanced ]]; then
    export GRASP_REQUIRE_BALANCED_PAIR=1
fi

cd "$output_dir"
printf 'y\n' > rangular.stdin
mpirun -n "$nprocs" "$binary_dir/rangular_mpi" \
    < rangular.stdin > rangular.stdout 2>&1

if [[ $initial_wave == estimate ]]; then
    printf 'y\n1\nprevious.w\n*\n2\n*\n4\n*\n4\n' > rwfnestimate.stdin
    "$binary_dir/rwfnestimate" \
        < rwfnestimate.stdin > rwfnestimate.stdout 2>&1
fi

printf 'y\n1-2\n1\n1-3\n1\n1-2\n%s\n%s\n\n100\n' \
    "$level_weight" "$varied" > rmcdhf.stdin
set +e
mpirun -n "$nprocs" "$binary_dir/rmcdhf_mpi" \
    < rmcdhf.stdin > rmcdhf.stdout 2>&1
rmcdhf_status=$?
set -e
printf '%s\n' "$rmcdhf_status" > rmcdhf.exitcode

python3 "$repo_root/test/rmcdhf_orbopt/compare_rmcdhf.py" \
    "$output_dir/orbopt_trace.csv" > "$output_dir/orbopt_summary.csv"
if [[ $rmcdhf_status -ne 0 ]]; then
    if [[ ${GRASP_EXPECT_RMCDHF_FAILURE:-0} == 1 ]]; then
        echo "completed expected failure: $case_name $mode AS$stage ($nprocs ranks)"
        echo "results: $output_dir"
        exit 0
    fi
    echo "rmcdhf_mpi failed with exit code $rmcdhf_status" >&2
    exit "$rmcdhf_status"
fi
comparison_args=()
if [[ $mode == minus_only || $mode == balanced ]]; then
    comparison_args+=(--allow-energy-differences)
fi
python3 "$repo_root/test/rmcdhf_orbopt/compare_sum.py" \
    "$output_dir/rmcdhf.sum" "$output_dir/archived.sum" \
    "${comparison_args[@]}" \
    > "$output_dir/archive_comparison.csv"

echo "completed: $case_name $mode AS$stage ($nprocs ranks, $initial_wave wave)"
echo "results: $output_dir"
