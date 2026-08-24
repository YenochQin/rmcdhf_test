#!/usr/bin/env bash
# Run one archived-data regression without modifying its source fixture.
set -euo pipefail

if [[ $# -lt 3 || $# -gt 6 ]]; then
    echo "usage: $0 <ni_i|ni_ca_like|cl_i> <optimized|nv|minus_only|balanced> <output-dir> [nprocs] [estimate|archived] [stage]" >&2
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
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
rmcdhf_bindir=${GRASP_RMCDHF_MPI_BINDIR:-${GRASP_BINDIR:-$repo_root/build-debug/bin}}
graspkit_tools=${GRASPKITTOOLS:-$repo_root/../graspkit-tools}
graspkit_python=${GRASPKIT_PYTHON:-$graspkit_tools/.venv/bin/python}
data_root=$repo_root/test/data
max_stage=2
asf_selection=$'1-2\n1\n1-3\n1\n1-2'
isodata_source=

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
    cl_i:optimized)
        source_dir=$data_root/Cl_I/o1_vv1
        prefix=o1_vv
        varied_as1='4s,4p,3d'
        varied_as2='5s,5p,4d,4f'
        varied_as3='6s,6p,5d,5f,5g'
        varied_as4='7s,7p,6d,6f,6g'
        varied_as5='8s,8p,7d,7f,7g'
        level_weight=5
        max_stage=5
        asf_selection=$'1\n1'
        isodata_source=$repo_root/test/rmcdhf_orbopt/fixtures/cl_isodata
        ;;
    cl_i:nv)
        source_dir=$data_root/Cl_I/o1_vv_no_varied
        prefix=o1_vv_no_varied_
        varied_as1=''
        varied_as2=''
        varied_as3=''
        varied_as4=''
        varied_as5=''
        level_weight=5
        max_stage=5
        asf_selection=$'1\n1'
        isodata_source=$repo_root/test/rmcdhf_orbopt/fixtures/cl_isodata
        ;;
    cl_i:minus_only)
        source_dir=$data_root/Cl_I/o1_vv1
        prefix=o1_vv
        varied_as1='4s,4p-,3d-'
        varied_as2='5s,5p-,4d-,4f-'
        varied_as3='6s,6p-,5d-,5f-,5g-'
        varied_as4='7s,7p-,6d-,6f-,6g-'
        varied_as5='8s,8p-,7d-,7f-,7g-'
        level_weight=5
        max_stage=5
        asf_selection=$'1\n1'
        isodata_source=$repo_root/test/rmcdhf_orbopt/fixtures/cl_isodata
        ;;
    cl_i:balanced)
        source_dir=$data_root/Cl_I/o1_vv1
        prefix=o1_vv
        varied_as1='4s,4p-,4p,3d-,3d'
        varied_as2='5s,5p-,5p,4d-,4d,4f-,4f'
        varied_as3='6s,6p-,6p,5d-,5d,5f-,5f,5g-,5g'
        varied_as4='7s,7p-,7p,6d-,6d,6f-,6f,6g-,6g'
        varied_as5='8s,8p-,8p,7d-,7d,7f-,7f,7g-,7g'
        level_weight=5
        max_stage=5
        asf_selection=$'1\n1'
        isodata_source=$repo_root/test/rmcdhf_orbopt/fixtures/cl_isodata
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

if ! [[ $stage =~ ^[1-9][0-9]*$ ]] || (( stage > max_stage )); then
    echo "stage must be between 1 and $max_stage for $case_name" >&2
    exit 2
fi
level_weight=${GRASP_LEVEL_WEIGHT:-$level_weight}
if [[ $level_weight != 1 && $level_weight != 5 ]]; then
    echo "GRASP_LEVEL_WEIGHT must be 1 (equal) or 5 (statistical)" >&2
    exit 2
fi

rcsf_name=${prefix}as${stage}.c
wave_name=${prefix}as$((stage - 1)).w
archived_sum=${prefix}as${stage}.sum
archived_wave=${prefix}as${stage}.w
varied_name=varied_as${stage}
varied=${!varied_name}

mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)
mpi_tmp=$output_dir/mpi_tmp
mkdir "$mpi_tmp"

if [[ -z $isodata_source ]]; then
    isodata_source=$source_dir/isodata
fi
cp "$isodata_source" "$output_dir/isodata"
cp "$source_dir/$rcsf_name" "$output_dir/rcsf.inp"
previous_wave=${GRASP_PREVIOUS_WAVE:-$source_dir/$wave_name}
if [[ ! -f $previous_wave ]]; then
    echo "previous wavefunction does not exist: $previous_wave" >&2
    exit 2
fi
cp "$previous_wave" "$output_dir/previous.w"
cp "$source_dir/$archived_sum" "$output_dir/archived.sum"
if [[ $initial_wave == archived ]]; then
    cp "$source_dir/$archived_wave" "$output_dir/rwfn.inp"
fi

source /usr/share/Modules/init/bash
module load mpi/openmpi-x86_64
module load "${GRASP_MODULE:-grasp/grasp_2990_NNNP}"
if ! command -v rangular_mpi >/dev/null 2>&1; then
    echo "missing module-provided executable: rangular_mpi" >&2
    exit 2
fi
if ! command -v rwfnestimate >/dev/null 2>&1; then
    echo "missing module-provided executable: rwfnestimate" >&2
    exit 2
fi
for executable in rsave jj2lsj rlevels; do
    if ! command -v "$executable" >/dev/null 2>&1; then
        echo "missing module-provided executable: $executable" >&2
        exit 2
    fi
done
rhfs_launcher=()
if command -v rhfs_mpi >/dev/null 2>&1; then
    rhfs_launcher=(mpirun -n "$nprocs" rhfs_mpi)
elif command -v rhfs >/dev/null 2>&1; then
    echo "warning: module has no rhfs_mpi; using serial rhfs for post-processing" >&2
    rhfs_launcher=(rhfs)
else
    echo "missing module-provided executable: rhfs_mpi (or fallback rhfs)" >&2
    exit 2
fi
if [[ ! -x $rmcdhf_bindir/rmcdhf_mpi ]]; then
    echo "missing repository executable: $rmcdhf_bindir/rmcdhf_mpi" >&2
    exit 2
fi
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
mpirun -n "$nprocs" rangular_mpi \
    < rangular.stdin > rangular.stdout 2>&1

if [[ $initial_wave == estimate ]]; then
    printf 'y\n1\nprevious.w\n*\n2\n*\n4\n*\n4\n' > rwfnestimate.stdin
    rwfnestimate \
        < rwfnestimate.stdin > rwfnestimate.stdout 2>&1
fi

printf 'y\n%s\n%s\n%s\n\n100\n' \
    "$asf_selection" "$level_weight" "$varied" > rmcdhf.stdin
set +e
mpirun -n "$nprocs" "$rmcdhf_bindir/rmcdhf_mpi" \
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

# Reproduce the standard GRASP post-processing chain.  rsave consumes the
# current rmcdhf.sum/rwfn.inp pair, jj2lsj creates the LSJ-labelled .m file,
# rhfs_mpi writes the hyperfine/LSJ companion, and rlevels emits the readable
# level table consumed by graspkit-tools.
result_name=${prefix}as${stage}
rsave "$result_name" > rsave.stdout 2>&1
printf '%s\nn\ny\ny\n' "$result_name" | jj2lsj > jj2lsj.stdout 2>&1
"${rhfs_launcher[@]}" "$result_name" --nonci > rhfs.stdout 2>&1
rlevels "$result_name.m" | tee "$result_name.level"
if [[ ! -f $graspkit_tools/pyscript/read_level_to_csv.py ]]; then
    echo "missing level converter: $graspkit_tools/pyscript/read_level_to_csv.py" >&2
    exit 2
fi
if [[ ! -x $graspkit_python ]]; then
    graspkit_python=python3
fi
"$graspkit_python" "$graspkit_tools/pyscript/read_level_to_csv.py" \
    -f "$result_name.level" -lsj -gj \
    -o "${result_name}_rmcdhf.csv"
convergence_mode=legacy
case ${GRASP_STRICT_SCF:-0} in
    1|true|TRUE|yes|YES|on|ON) convergence_mode=strict ;;
esac
python3 "$repo_root/test/rmcdhf_orbopt/check_strict_scf.py" \
    "$output_dir/orbopt_trace.csv" --mode "$convergence_mode" \
    > "$output_dir/convergence_check.txt"
if [[ ${GRASP_TRACE_RWFN:-0} == 1 ]]; then
    python3 "$repo_root/test/rmcdhf_orbopt/compare_rwfn.py" \
        "$output_dir/rwfn.inp" "$output_dir"/rwfn.out.iter* \
        > "$output_dir/rwfn_metrics.csv"
    python3 "$repo_root/test/rmcdhf_orbopt/crosscheck_rwfn.py" \
        "$output_dir/orbopt_trace.csv" "$output_dir/rwfn_metrics.csv" \
        > "$output_dir/rwfn_crosscheck.csv"
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
