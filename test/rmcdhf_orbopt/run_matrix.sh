#!/usr/bin/env bash
# Run the reproducible orbital-optimization matrices.
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: $0 <output-root> [smoke|cl|damping|full]" >&2
    exit 2
fi

output_root=$1
profile=${2:-smoke}
if [[ $profile != smoke && $profile != cl && $profile != damping && $profile != full ]]; then
    echo "profile must be 'smoke', 'cl', 'damping', or 'full'" >&2
    exit 2
fi
if [[ -e $output_root ]]; then
    echo "output root already exists: $output_root" >&2
    exit 2
fi

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
runner=$repo_root/test/rmcdhf_orbopt/run_data_case.sh
checker=$repo_root/test/rmcdhf_orbopt/check_strict_scf.py
mkdir -p "$output_root"
output_root=$(cd "$output_root" && pwd)

if [[ -n ${GRASP_BUILD_DIR:-} ]]; then
    source /usr/share/Modules/init/bash
    module load mpi/openmpi-x86_64
    cmake --build "$GRASP_BUILD_DIR" --target rmcdhf_mpi -j"${GRASP_BUILD_JOBS:-4}"
fi

run_case() {
    local family=$1 mode=$2 stage=$3 ranks=$4 tag=$5
    shift 5
    env "$@" bash "$runner" "$family" "$mode" \
        "$output_root/$tag" "$ranks" estimate "$stage"
}

if [[ $profile == smoke || $profile == full ]]; then
    # Quick code-path coverage on the compact Ni/Ca-like fixture.
    run_case ni_ca_like nv 1 1 ni_ca_as1_b0
    run_case ni_ca_like optimized 1 1 ni_ca_as1_b1
    run_case ni_ca_like minus_only 1 1 ni_ca_as1_b2
    run_case ni_ca_like balanced 1 1 ni_ca_as1_b3
    run_case ni_ca_like balanced 1 1 ni_ca_as1_b4 GRASP_ORBITAL_DAMPING=-0.5
    run_case ni_ca_like balanced 1 1 ni_ca_as1_b5 GRASP_DEFER_ORTHY=1 \
        GRASP_EXPECT_RMCDHF_FAILURE=1
    run_case ni_ca_like balanced 1 1 ni_ca_as1_b6 GRASP_STRICT_METHOD3=1
    run_case ni_ca_like balanced 1 1 ni_ca_as1_strict GRASP_STRICT_SCF=1
    python3 "$checker" "$output_root/ni_ca_as1_b3/orbopt_trace.csv" --mode legacy
    python3 "$checker" "$output_root/ni_ca_as1_strict/orbopt_trace.csv" --mode strict
fi

if [[ $profile == cl || $profile == full ]]; then
    run_case cl_i nv 1 1 cl_as1_b0
    run_case cl_i optimized 1 1 cl_as1_b1
    run_case cl_i minus_only 1 1 cl_as1_b2
    run_case cl_i balanced 1 1 cl_as1_b3
    run_case cl_i balanced 1 1 cl_as1_b4 GRASP_ORBITAL_DAMPING=-0.5 \
        GRASP_TRACE_RWFN=1
    run_case cl_i balanced 1 1 cl_as1_b5 GRASP_DEFER_ORTHY=1 \
        GRASP_EXPECT_RMCDHF_FAILURE=1
    run_case cl_i balanced 1 1 cl_as1_b6 GRASP_STRICT_METHOD3=1
    run_case cl_i balanced 1 1 cl_as1_strict GRASP_STRICT_SCF=1
    run_case cl_i balanced 1 1 cl_as1_b8_equal \
        GRASP_ORBITAL_DAMPING=-0.5 GRASP_LEVEL_WEIGHT=1
    python3 "$checker" "$output_root/cl_as1_b3/orbopt_trace.csv" --mode legacy
    python3 "$checker" "$output_root/cl_as1_strict/orbopt_trace.csv" --mode strict
    GRASP_SERIAL_BINDIR=${GRASP_SERIAL_BINDIR:-$repo_root/build-debug/bin} \
        bash "$repo_root/test/rmcdhf_orbopt/run_serial_comparison.sh" \
        "$output_root/cl_as1_b3" "$output_root/cl_as1_b3_serial"
    python3 "$repo_root/test/rmcdhf_orbopt/compare_fine_structure.py" \
        --j-values 1/2,3/2 --parity - \
        B0="$output_root/cl_as1_b0/rmcdhf.sum" \
        B1="$output_root/cl_as1_b1/rmcdhf.sum" \
        B2="$output_root/cl_as1_b2/rmcdhf.sum" \
        B3="$output_root/cl_as1_b3/rmcdhf.sum" \
        B4="$output_root/cl_as1_b4/rmcdhf.sum" \
        B6="$output_root/cl_as1_b6/rmcdhf.sum" \
        STRICT="$output_root/cl_as1_strict/rmcdhf.sum" \
        B8_EQUAL="$output_root/cl_as1_b8_equal/rmcdhf.sum" \
        > "$output_root/cl_as1_fine_structure.csv"
fi

if [[ $profile == full ]]; then
    for family in ni_ca_like ni_i; do
        for stage in 1 2; do
            for mode in nv optimized minus_only balanced; do
                tag=${family}_as${stage}_${mode}
                run_case "$family" "$mode" "$stage" 1 "$tag"
            done
            tag=${family}_as${stage}_balanced_damped
            run_case "$family" balanced "$stage" 1 "$tag" \
                GRASP_ORBITAL_DAMPING=-0.5
        done
    done

    previous_wave=$output_root/cl_as1_b4/rwfn.out
    for stage in 2 3 4 5; do
        tag=cl_as${stage}_balanced_damped
        ranks=1
        extra_env=()
        if [[ $stage == 5 ]]; then
            ranks=4
            extra_env+=(GRASP_OMP_THREADS=12)
        fi
        run_case cl_i balanced "$stage" "$ranks" "$tag" \
            GRASP_ORBITAL_DAMPING=-0.5 GRASP_PREVIOUS_WAVE="$previous_wave" \
            "${extra_env[@]}"
        previous_wave=$output_root/$tag/rwfn.out
    done

    for ranks in 2 4; do
        run_case cl_i balanced 1 "$ranks" "cl_as1_b4_np${ranks}" \
            GRASP_ORBITAL_DAMPING=-0.5 GRASP_OMP_THREADS=12
    done

    # Process-count repeatability uses the balanced AS2 candidate selected by
    # the diagnostic experiments.  The 1-rank result is already present.
    for ranks in 2 4; do
        run_case ni_ca_like balanced 2 "$ranks" \
            "ni_ca_as2_balanced_np${ranks}"
        run_case ni_i balanced 2 "$ranks" "ni_i_as2_balanced_np${ranks}"
    done
fi

if [[ $profile == damping ]]; then
    damping_ranks=${GRASP_DAMPING_RANKS:-1}
    damping_threads=${GRASP_DAMPING_THREADS:-1}
    if ! [[ $damping_ranks =~ ^[1-9][0-9]*$ ]] || \
       ! [[ $damping_threads =~ ^[1-9][0-9]*$ ]]; then
        echo "GRASP_DAMPING_RANKS and GRASP_DAMPING_THREADS must be positive integers" >&2
        exit 2
    fi
    for damping in -0.2 -0.5 -0.8; do
        case $damping in
            -0.2) damping_tag=02 ;;
            -0.5) damping_tag=05 ;;
            -0.8) damping_tag=08 ;;
        esac
        run_case cl_i balanced 1 "$damping_ranks" \
            "cl_as1_damp_${damping_tag}" \
            GRASP_ORBITAL_DAMPING="$damping" \
            GRASP_OMP_THREADS="$damping_threads"
        run_case ni_ca_like balanced 2 "$damping_ranks" \
            "ni_ca_as2_damp_${damping_tag}" \
            GRASP_ORBITAL_DAMPING="$damping" \
            GRASP_OMP_THREADS="$damping_threads"
        run_case ni_i balanced 2 "$damping_ranks" \
            "ni_i_as2_damp_${damping_tag}" \
            GRASP_ORBITAL_DAMPING="$damping" \
            GRASP_OMP_THREADS="$damping_threads"
    done

    summarizer=$repo_root/test/rmcdhf_orbopt/summarize_damping.py
    python3 "$summarizer" --j-values 1/2,3/2 --parity - \
        D02="$output_root/cl_as1_damp_02" \
        D05="$output_root/cl_as1_damp_05" \
        D08="$output_root/cl_as1_damp_08" \
        > "$output_root/cl_as1_damping.csv"
    python3 "$summarizer" \
        D02="$output_root/ni_ca_as2_damp_02" \
        D05="$output_root/ni_ca_as2_damp_05" \
        D08="$output_root/ni_ca_as2_damp_08" \
        > "$output_root/ni_ca_as2_damping.csv"
    python3 "$summarizer" \
        D02="$output_root/ni_i_as2_damp_02" \
        D05="$output_root/ni_i_as2_damp_05" \
        D08="$output_root/ni_i_as2_damp_08" \
        > "$output_root/ni_i_as2_damping.csv"
fi

printf 'profile,%s\nstatus,complete\n' "$profile" > "$output_root/matrix_status.csv"
echo "matrix complete: $output_root"
