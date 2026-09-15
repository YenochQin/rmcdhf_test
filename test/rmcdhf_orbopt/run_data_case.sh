#!/usr/bin/env bash
# Run one archived-data regression without modifying its source fixture.
set -euo pipefail

if [[ $# -lt 3 || $# -gt 6 ]]; then
    echo "usage: $0 <ni_i|ni_ca_like|cl_i|fe_i> <optimized|nv|minus_only|balanced> <output-dir> [nprocs] [estimate|archived] [stage]" >&2
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
if [[ $initial_wave != estimate && $initial_wave != archived ]]; then
    echo "initial wave must be 'estimate' or 'archived'" >&2
    exit 2
fi
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
storage_root=$(realpath -m "$repo_root/../data/rmcdhf_test_data")
# Keep the workspace fixture as the default.  Large external fixtures (for
# example Fe I on the NVMe validation disk) can be selected without copying
# their multi-gigabyte CSF files into the repository:
#   GRASP_TEST_DATA_ROOT=/path/to/rmcdhf_test_cal
data_root=${GRASP_TEST_DATA_ROOT:-$storage_root/inputs}
external_fixture=0
if [[ -n ${GRASP_TEST_DATA_ROOT:-} ]]; then
    external_fixture=1
fi
results_root=$storage_root/results
mkdir -p "$results_root"
if [[ $output_dir != /* ]]; then
    output_dir=$results_root/$output_dir
fi
output_dir=$(realpath -m "$output_dir")
case "$output_dir" in
    "$results_root"/*) ;;
    *)
        echo "output directory must be below $results_root: $output_dir" >&2
        exit 2
        ;;
esac
if [[ -e $output_dir ]]; then
    echo "output directory already exists: $output_dir" >&2
    exit 2
fi
stage_transaction=0
case ${GRASP_STAGE_TRANSACTION:-0} in
    1|true|TRUE|yes|YES|on|ON) stage_transaction=1 ;;
esac
stage_root=
stage_config=${GRASP_STAGE_CONFIG:-}
stage_rci_stdin=${GRASP_STAGE_RCI_STDIN:-}
previous_stage=${GRASP_PREVIOUS_STAGE:-}
rmcdhf_bindir=${GRASP_RMCDHF_MPI_BINDIR:-${GRASP_BINDIR:-$repo_root/build-debug/bin}}
graspkit_tools=${GRASPKITTOOLS:-$repo_root/../graspkit-tools}
graspkit_python=${GRASPKIT_PYTHON:-$graspkit_tools/.venv/bin/python}
stage_guard=$graspkit_tools/scripts/grasp_regular_cal/orbopt_stage_guard.py
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
        if (( external_fixture )); then
            source_dir=$data_root/Ni_Ca-like/e1_cv
        else
            source_dir=$data_root/Ni_Ca-like/even1_cv
        fi
        prefix=e1_cv
        varied_as1='4s,4p,4d,4f'
        varied_as2='5s,5p,5d,5f,5g'
        level_weight=5
        ;;
    cl_i:optimized)
        if (( external_fixture )); then
            source_dir=$data_root/Cl_I/o1_cc1
            prefix=o1_cc1
        else
            source_dir=$data_root/Cl_I/o1_vv1
            prefix=o1_vv
        fi
        if (( external_fixture )); then
            varied_as1='4s,4p,4d,4f'
            varied_as2='5s,5p,5d,5f,5g'
            varied_as3='6s,6p,6d,6f,6g'
            varied_as4='7s,7p,7d,7f,7g'
            varied_as5='8s,8p,8d,8f,8g'
        else
            varied_as1='4s,4p,3d'
            varied_as2='5s,5p,4d,4f'
            varied_as3='6s,6p,5d,5f,5g'
            varied_as4='7s,7p,6d,6f,6g'
            varied_as5='8s,8p,7d,7f,7g'
        fi
        level_weight=5
        max_stage=5
        asf_selection=$'1\n1'
        isodata_source=$repo_root/test/rmcdhf_orbopt/fixtures/cl_isodata
        if (( external_fixture )); then
            isodata_source=$source_dir/isodata
        fi
        ;;
    cl_i:nv)
        if (( external_fixture )); then
            source_dir=$data_root/Cl_I/o1_cc1_NV
            prefix=o1_cc1_NV
        else
            source_dir=$data_root/Cl_I/o1_vv_no_varied
            prefix=o1_vv_no_varied_
        fi
        varied_as1=''
        varied_as2=''
        varied_as3=''
        varied_as4=''
        varied_as5=''
        level_weight=5
        max_stage=5
        asf_selection=$'1\n1'
        isodata_source=$repo_root/test/rmcdhf_orbopt/fixtures/cl_isodata
        if (( external_fixture )); then
            isodata_source=$source_dir/isodata
        fi
        ;;
    cl_i:minus_only)
        if (( external_fixture )); then
            source_dir=$data_root/Cl_I/o1_cc1
            prefix=o1_cc1
        else
            source_dir=$data_root/Cl_I/o1_vv1
            prefix=o1_vv
        fi
        varied_as1='4s,4p-,3d-'
        varied_as2='5s,5p-,4d-,4f-'
        varied_as3='6s,6p-,5d-,5f-,5g-'
        varied_as4='7s,7p-,6d-,6f-,6g-'
        varied_as5='8s,8p-,7d-,7f-,7g-'
        level_weight=5
        max_stage=5
        asf_selection=$'1\n1'
        isodata_source=$repo_root/test/rmcdhf_orbopt/fixtures/cl_isodata
        if (( external_fixture )); then
            isodata_source=$source_dir/isodata
        fi
        ;;
    cl_i:balanced)
        if (( external_fixture )); then
            source_dir=$data_root/Cl_I/o1_cc1
            prefix=o1_cc1
        else
            source_dir=$data_root/Cl_I/o1_vv1
            prefix=o1_vv
        fi
        varied_as1='4s,4p-,4p,3d-,3d'
        varied_as2='5s,5p-,5p,4d-,4d,4f-,4f'
        varied_as3='6s,6p-,6p,5d-,5d,5f-,5f,5g-,5g'
        varied_as4='7s,7p-,7p,6d-,6d,6f-,6f,6g-,6g'
        varied_as5='8s,8p-,8p,7d-,7d,7f-,7f,7g-,7g'
        level_weight=5
        max_stage=5
        asf_selection=$'1\n1'
        isodata_source=$repo_root/test/rmcdhf_orbopt/fixtures/cl_isodata
        if (( external_fixture )); then
            isodata_source=$source_dir/isodata
        fi
        ;;
    ni_ca_like:nv)
        source_dir=$data_root/Ni_Ca-like/e1_cv_NV
        prefix=e1_cv_NV
        varied_as1=''
        varied_as2=''
        level_weight=5
        ;;
    ni_ca_like:minus_only)
        if (( external_fixture )); then
            source_dir=$data_root/Ni_Ca-like/e1_cv
        else
            source_dir=$data_root/Ni_Ca-like/even1_cv
        fi
        prefix=e1_cv
        varied_as1='4s,4p-,4d-,4f-'
        varied_as2='5s,5p-,5d-,5f-,5g-'
        level_weight=5
        ;;
    ni_ca_like:balanced)
        if (( external_fixture )); then
            source_dir=$data_root/Ni_Ca-like/e1_cv
        else
            source_dir=$data_root/Ni_Ca-like/even1_cv
        fi
        prefix=e1_cv
        varied_as1='4s,4p-,4p,4d-,4d,4f-,4f'
        varied_as2='5s,5p-,5p,5d-,5d,5f-,5f,5g-,5g'
        level_weight=5
        ;;
    fe_i:optimized)
        source_dir=$data_root/Fe_I/e1_vv3
        prefix=e1_vv3
        asf_selection=$'1-5\n1-4\n1-8\n1-6\n1-7\n1-2\n1-2'
        varied_as1='4s,4p,4d,4f'
        varied_as2='5s,5p,5d,5f,5g'
        varied_as3='6s,6p,6d,6f,6g'
        varied_as4='7s,7p,7d,7f,7g'
        varied_as5='8s,8p,8d,8f,8g'
        level_weight=5
        max_stage=5
        ;;
    fe_i:nv)
        source_dir=$data_root/Fe_I/e1_vv3_NV
        prefix=e1_vv3_NV
        asf_selection=$'1-5\n1-4\n1-8\n1-6\n1-7\n1-2\n1-2'
        varied_as1=''
        varied_as2=''
        varied_as3=''
        varied_as4=''
        varied_as5=''
        level_weight=5
        max_stage=5
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
if [[ -n ${GRASP_ASF_SELECTION:-} ]]; then
    asf_selection=$GRASP_ASF_SELECTION
fi
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
if [[ ${GRASP_VARIED_OVERRIDE+x} ]]; then
    varied=$GRASP_VARIED_OVERRIDE
fi
previous_wave=${GRASP_PREVIOUS_WAVE:-$source_dir/$wave_name}
if [[ ! -f $previous_wave ]]; then
    echo "previous wavefunction does not exist: $previous_wave" >&2
    exit 2
fi
if (( stage_transaction )); then
    if [[ -z $stage_config || ! -f $stage_config ]]; then
        echo "GRASP_STAGE_CONFIG must name a case acceptance JSON file" >&2
        exit 2
    fi
    if [[ -z $stage_rci_stdin || ! -f $stage_rci_stdin ]]; then
        echo "stage transaction requires GRASP_STAGE_RCI_STDIN" >&2
        exit 2
    fi
    stage_root=$output_dir
    anchor_type=${GRASP_ANCHOR_TYPE:-tf_baseline}
    prepare_args=(
        "$stage_root" --case "$case_name" --stage "AS$stage"
        --anchor-type "$anchor_type" --csf "$source_dir/$rcsf_name"
        --previous-wave "$previous_wave" --acceptance-config "$stage_config"
        --rci-stdin "$stage_rci_stdin"
        --target-state-spec "${GRASP_ROUND_TARGET_STATES:-}"
        --state-selection "$asf_selection" --weights "$level_weight"
    )
    if [[ -n $previous_stage ]]; then
        prepare_args+=(--previous-stage "$previous_stage")
    fi
    "$graspkit_python" "$stage_guard" prepare-stage \
        "${prepare_args[@]}" \
        >/dev/null
    output_dir=$stage_root/candidate
    stage_rci_stdin=$stage_root/anchor/rci.stdin
    GRASP_TARGET_STATE_LABELS=$(python3 -c \
        'import json,sys; print(",".join(str(item["label"]) for item in json.load(open(sys.argv[1]))["target_levels"]))' \
        "$stage_config")
    export GRASP_TARGET_STATE_LABELS
    export GRASP_FIXED_REFERENCE_PROXY=1
fi

mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)
mpi_tmp=${GRASP_MPI_TMP:-/home/workstation2/caltmp}
runner_stage=input_setup
runner_status=running
record_runner_status() {
    local runner_exit=$?
    local rmcdhf_exit=not_run
    [[ -f $output_dir/rmcdhf.exitcode ]] && rmcdhf_exit=$(<"$output_dir/rmcdhf.exitcode")
    printf '%s\n' "$runner_exit" > "$output_dir/runner.exitcode"
    if (( runner_exit == 0 )); then
        runner_status=complete
    elif [[ $runner_status == running ]]; then
        runner_status=failed
    fi
    printf 'stage,status,runner_exit,rmcdhf_exit\n%s,%s,%s,%s\n' \
        "$runner_stage" "$runner_status" "$runner_exit" "$rmcdhf_exit" \
        > "$output_dir/status.csv"
    if (( stage_transaction )) && [[ ${GRASP_PREPARE_ONLY:-0} != 1 ]] \
        && [[ ! -f $stage_root/next_restart.json ]]; then
        set +e
        "$graspkit_python" "$stage_guard" \
            validate-stage "$stage_root" --config "$stage_config" \
            > "$stage_root/validation.stdout" 2> "$stage_root/validation.stderr"
        validation_exit=$?
        set -e
        if (( runner_exit == 0 && validation_exit != 0 )); then
            runner_exit=$validation_exit
        fi
    fi
    trap - EXIT
    exit "$runner_exit"
}
trap record_runner_status EXIT

if [[ -z $isodata_source ]]; then
    isodata_source=$source_dir/isodata
fi
if [[ -n ${GRASP_ISODATA_SOURCE:-} ]]; then
    isodata_source=$GRASP_ISODATA_SOURCE
fi
if [[ $(head -n 1 "$isodata_source") != 'Atomic number:' ]]; then
    echo "invalid isodata header: $isodata_source" >&2
    exit 2
fi
cp "$isodata_source" "$output_dir/isodata"
cp "$source_dir/$rcsf_name" "$output_dir/rcsf.inp"
allow_unbalanced=0
case ${GRASP_ALLOW_UNBALANCED:-0} in
    1|true|TRUE|yes|YES|on|ON) allow_unbalanced=1 ;;
esac
selection_args=(
    --varied "$varied"
    --rcsf "$output_dir/rcsf.inp"
    --manifest "$output_dir/selection_manifest.json"
    --case "$case_name"
    --stage "AS$stage"
)
if (( allow_unbalanced )); then
    selection_args+=(--allow-unbalanced)
    export GRASP_REQUIRE_BALANCED_PAIR=0
    export GRASP_ALLOW_UNBALANCED=1
else
    # The production runner always enables the executable's independent
    # check.  Historical direct executable use keeps its default-off path.
    export GRASP_REQUIRE_BALANCED_PAIR=1
    unset GRASP_ALLOW_UNBALANCED
fi
runner_stage=input_gate
set +e
"$graspkit_python" "$stage_guard" selection \
    "${selection_args[@]}"
selection_status=$?
set -e
if (( selection_status != 0 )); then
    runner_status=rejected_input
    echo "production input gate rejected the varied list; set GRASP_ALLOW_UNBALANCED=1 only for an explicit diagnostic run" >&2
    exit "$selection_status"
fi
cp "$previous_wave" "$output_dir/previous.w"
cp "$source_dir/$archived_sum" "$output_dir/archived.sum"
if [[ $initial_wave == archived ]]; then
    cp "$source_dir/$archived_wave" "$output_dir/rwfn.inp"
fi

if [[ ${GRASP_DEBUG_EIGENVECTORS:-0} == 1 ]]; then
    # Enable only LDBPG(5), which writes each NEWCO CI-vector block to
    # rscf92.dbg. Keep all other debug streams disabled.
    {
        printf 'n\ny\n\n'
        printf 'n\n%.0s' {1..4}
        printf 'y\n'
        printf 'n\n%.0s' {1..16}
        # NDEF=1 also asks for the radial-grid and ACCY overrides before
        # GETOLD reads the ASF/weight/orbital selections.
        printf 'n\nn\n'
        printf '%s\n%s\n%s\n\n100\n' \
            "$asf_selection" "$level_weight" "$varied"
        printf 'n\n'
        # With non-default settings SCF asks for the orthonormalisation
        # order; 1 preserves the historical update-order behaviour.
        printf '1\n'
    } > "$output_dir/rmcdhf.stdin"
else
    printf 'y\n%s\n%s\n%s\n\n100\n' \
        "$asf_selection" "$level_weight" "$varied" > "$output_dir/rmcdhf.stdin"
fi
# Prepare the exact inputs without launching MPI for a submission preflight.
if [[ ${GRASP_PREPARE_ONLY:-0} == 1 ]]; then
    runner_stage=prepared
    echo "prepared: $case_name $mode AS$stage -> $output_dir"
    exit 0
fi

runner_stage=runtime_setup
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
if (( stage_transaction )) && ! command -v rci >/dev/null 2>&1; then
    echo "missing module-provided executable: rci" >&2
    exit 2
fi
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

# The cluster's working launcher is srun/PMIx (see the archived Cl I
# mcdhfmpi.sh).  Keep mpirun only as a non-Slurm fallback for local probes.
if [[ -n ${SLURM_JOB_ID:-} ]]; then
    grasp_mpi_launcher=(srun --mpi=pmix --cpu-bind=thread --ntasks="$nprocs")
else
    grasp_mpi_launcher=(mpirun -n "$nprocs")
fi
cd "$output_dir"
mkdisks "$nprocs" "$mpi_tmp"
expected_disk="'$output_dir'"
actual_disk=$(head -n 1 disks)
if [[ $actual_disk != "$expected_disk" ]]; then
    echo "invalid disks serial I/O directory: expected $expected_disk, got $actual_disk" >&2
    exit 2
fi
if [[ ! -f rcsf.inp ]]; then
    echo "missing rcsf.inp in calculation directory: $output_dir" >&2
    exit 2
fi
printf 'y\n' > rangular.stdin
"${grasp_mpi_launcher[@]}" rangular_mpi \
    < rangular.stdin > rangular.stdout 2>&1

if [[ $initial_wave == estimate ]]; then
    rwfnestimate_method=${GRASP_RWFNESTIMATE_METHOD:-2}
    printf 'y\n1\nprevious.w\n*\n%s\n*\n4\n*\n4\n' "$rwfnestimate_method" > rwfnestimate.stdin
    rwfnestimate \
        < rwfnestimate.stdin > rwfnestimate.stdout 2>&1
fi
if (( stage_transaction )); then
    run_stage_fixed_rci() {
        local fixed_work=$1 fixed_wave=$2
        local fixed_mpi_tmp=$fixed_work/mpi_tmp
        mkdir -p "$fixed_work"
        mkdir -p "$fixed_mpi_tmp"
        cp "$output_dir/isodata" "$fixed_work/isodata"
        cp "$output_dir/rcsf.inp" "$fixed_work/baseline.c"
        cp "$fixed_wave" "$fixed_work/baseline.w"
        (
            cd "$fixed_work"
            # RCI creates its own MCP data.  Never reuse RMCDHF's MPI_TMP:
            # doing so overwrites the 46-rank rangular_mpi MCP files.
            mkdisks 1 "$fixed_mpi_tmp" > mkdisks.stdout 2>&1
            rci < "$stage_rci_stdin" > rci.stdout 2>&1
            test -s baseline.cm -a -s baseline.csum
            printf '%s\ny\ny\ny\n' baseline | jj2lsj \
                > jj2lsj.stdout 2>&1
            rlevels baseline.cm > baseline.level
            "$graspkit_python" \
                "$graspkit_tools/pyscript/read_level_to_csv.py" \
                -f baseline.level -lsj -o baseline_rci.csv
            test -s baseline_rci.csv
        )
    }
    runner_stage=fixed_rci_baseline
    stage_baseline_dir=$stage_root/baseline_build
    run_stage_fixed_rci "$stage_baseline_dir" "$output_dir/rwfn.inp"
    stage_baseline_levels=$stage_baseline_dir/baseline_rci.csv
    anchor_fields=$("$graspkit_python" \
        "$stage_guard" finalize-anchor \
        "$stage_root" --tf-wave "$output_dir/rwfn.inp" \
        --selection-manifest "$output_dir/selection_manifest.json" \
        --baseline-levels "$stage_baseline_levels")
    IFS=$'\t' read -r GRASP_ANCHOR_ID GRASP_ANCHOR_TYPE GRASP_ANCHOR_HASH \
        <<< "$anchor_fields"
    export GRASP_ANCHOR_ID GRASP_ANCHOR_TYPE GRASP_ANCHOR_HASH
fi

set +e
runner_stage=rmcdhf
rmcdhf_timeout=${GRASP_RMCDHF_TIMEOUT:-}
rmcdhf_kill_after=${GRASP_RMCDHF_KILL_AFTER:-30s}
if [[ -n $rmcdhf_timeout ]]; then
    # GNU timeout creates a separate process group for mpirun.  On timeout it
    # terminates the launcher and every rank, then escalates to KILL after the
    # grace period.  This also handles MPI launchers that hang while reaping
    # ranks after an expected ERROR STOP.
    if [[ ${GRASP_ABORT_ON_ORBOPT_ERROR:-0} == 1 ]]; then
        timeout --signal=TERM --kill-after="$rmcdhf_kill_after" \
            "$rmcdhf_timeout" "${grasp_mpi_launcher[@]}" \
            "$rmcdhf_bindir/rmcdhf_mpi" \
            < rmcdhf.stdin > rmcdhf.stdout 2>&1 &
        launcher_pid=$!
        while kill -0 "$launcher_pid" 2>/dev/null; do
            if grep -Eq 'ERROR STOP ORBOPT|rejection limit exceeded' rmcdhf.stdout 2>/dev/null; then
                # TERM the timeout wrapper; it forwards the signal to mpirun
                # and its process group, preventing a PRRTE reap hang.
                kill -TERM "$launcher_pid" 2>/dev/null || true
                break
            fi
            sleep 1
        done
        wait "$launcher_pid"
    else
        timeout --signal=TERM --kill-after="$rmcdhf_kill_after" \
            "$rmcdhf_timeout" "${grasp_mpi_launcher[@]}" \
            "$rmcdhf_bindir/rmcdhf_mpi" \
            < rmcdhf.stdin > rmcdhf.stdout 2>&1
    fi
else
    "${grasp_mpi_launcher[@]}" "$rmcdhf_bindir/rmcdhf_mpi" \
        < rmcdhf.stdin > rmcdhf.stdout 2>&1
fi
rmcdhf_status=$?
set -e
printf '%s\n' "$rmcdhf_status" > rmcdhf.exitcode
# Preserve the diagnostic unit written by rmcdhf_mpi before post-processing
# tools (notably rsave) rename or remove auxiliary files.
if [[ -f rmcdhf.log ]]; then
    cp -f rmcdhf.log rmcdhf_diagnostic.log
fi

# A missing trace must not mask the launcher's original failure code.
if [[ -s $output_dir/orbopt_trace.csv ]]; then
    python3 "$repo_root/test/rmcdhf_orbopt/compare_rmcdhf.py" \
        "$output_dir/orbopt_trace.csv" > "$output_dir/orbopt_summary.csv" || {
        if [[ $rmcdhf_status -eq 0 ]]; then exit 1; fi
    }
fi
if [[ $rmcdhf_status -ne 0 ]]; then
    if [[ $rmcdhf_status -eq 124 ]]; then
        runner_status=rejected_timeout
    else
        runner_status=rejected_rmcdhf
    fi
    if [[ ${GRASP_EXPECT_RMCDHF_FAILURE:-0} == 1 ]]; then
        runner_stage=expected_rmcdhf_failure
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
runner_stage=postprocess
rsave "$result_name" > rsave.stdout 2>&1
if [[ ! -f rmcdhf.sum && -f "$result_name.sum" ]]; then
    cp "$result_name.sum" rmcdhf.sum
fi
if [[ ! -f $graspkit_tools/pyscript/read_radial_wavefunction.py ]]; then
    echo "missing radial-wavefunction converter: $graspkit_tools/pyscript/read_radial_wavefunction.py" >&2
    exit 2
fi
if [[ ! -x $graspkit_python ]]; then
    graspkit_python=python3
fi
"$graspkit_python" "$graspkit_tools/pyscript/read_radial_wavefunction.py" \
    -f "$result_name.w"
printf '%s\nn\ny\ny\n' "$result_name" | jj2lsj > jj2lsj.stdout 2>&1
"${rhfs_launcher[@]}" "$result_name" --nonci > rhfs.stdout 2>&1
rlevels "$result_name.m" | tee "$result_name.level"
if [[ ! -f $graspkit_tools/pyscript/read_level_to_csv.py ]]; then
    echo "missing level converter: $graspkit_tools/pyscript/read_level_to_csv.py" >&2
    exit 2
fi
"$graspkit_python" "$graspkit_tools/pyscript/read_level_to_csv.py" \
    -f "$result_name.level" -lsj -gj \
    -o "${result_name}_rmcdhf.csv"
convergence_mode=legacy
case ${GRASP_STRICT_SCF:-0} in
    1|true|TRUE|yes|YES|on|ON) convergence_mode=strict ;;
esac
set +e
python3 "$repo_root/test/rmcdhf_orbopt/check_strict_scf.py" \
    "$output_dir/orbopt_trace.csv" --mode "$convergence_mode" \
    > "$output_dir/convergence_check.txt"
convergence_status=$?
set -e
printf '%s\n' "$convergence_status" > "$output_dir/convergence_check.exitcode"
if (( convergence_status != 0 )); then
    runner_stage=convergence
    runner_status=rejected_convergence
    echo "${convergence_mode} SCF convergence check failed; rmcdhf itself completed" >&2
    exit "$convergence_status"
fi
if (( stage_transaction )); then
    runner_stage=fixed_rci_candidate
    run_stage_fixed_rci "$output_dir/fixed_rci" \
        "$output_dir/$result_name.w"
fi
if [[ ${GRASP_TRACE_RWFN:-0} == 1 && -n $varied ]]; then
    python3 "$repo_root/test/rmcdhf_orbopt/compare_rwfn.py" \
        "$output_dir/rwfn.inp" "$output_dir"/rwfn.out.iter* \
        > "$output_dir/rwfn_metrics.csv"
    python3 "$repo_root/test/rmcdhf_orbopt/crosscheck_rwfn.py" \
        "$output_dir/orbopt_trace.csv" "$output_dir/rwfn_metrics.csv" \
        > "$output_dir/rwfn_crosscheck.csv"
fi
comparison_args=()
if [[ $mode == minus_only || $mode == balanced || ${GRASP_ALLOW_ENERGY_DIFFERENCES:-0} == 1 ]]; then
    comparison_args+=(--allow-energy-differences)
fi
if [[ ${GRASP_ALLOW_RADIAL_GRID_DIFFERENCE:-0} == 1 ]]; then
    comparison_args+=(--allow-radial-grid-difference)
fi
if [[ ${GRASP_ALLOW_LEVEL_DIFFERENCES:-0} == 1 ]]; then
    comparison_args+=(--allow-level-differences)
fi
python3 "$repo_root/test/rmcdhf_orbopt/compare_sum.py" \
    "$output_dir/rmcdhf.sum" "$output_dir/archived.sum" \
    "${comparison_args[@]}" \
    > "$output_dir/archive_comparison.csv"

runner_stage=candidate_complete
echo "completed: $case_name $mode AS$stage ($nprocs ranks, $initial_wave wave)"
echo "results: $output_dir"
