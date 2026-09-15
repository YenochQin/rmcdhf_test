#!/bin/zsh
# Minimal production-path probe for the new SCF-round transaction guard.
# It deliberately runs one Ni I AS2, one Ni/Ca-like AS2, and one Cl I AS1
# fixture; it does not repeat the completed isolation/RCI jobs.
#SBATCH -J rmcdhf-round-guard
#SBATCH -N 1
#SBATCH --ntasks-per-node=46
#SBATCH --cpus-per-task=1
#SBATCH -p batch
#SBATCH --time=08:00:00
#SBATCH --output=/home/workstation2/AppFiles/GraspKit-Workspace/data/rmcdhf_test_data/log/%j_%x.log
#SBATCH --error=/home/workstation2/AppFiles/GraspKit-Workspace/data/rmcdhf_test_data/log/%j_%x.log

. /usr/share/Modules/init/zsh
set -euo pipefail
module load mpi/openmpi-x86_64
module load grasp/grasp_2990_NNNP

root=/home/workstation2/AppFiles/GraspKit-Workspace
external=/home/workstation2/nvmesdd2T/rmcdhf_test_cal
export GRASPKITTOOLS=$root/graspkit-tools
export GRASP_TEST_DATA_ROOT=$external
export PATH=${GRASPKITTOOLS}/scripts:${PATH}
unset VIRTUAL_ENV _OLD_VIRTUAL_PATH _OLD_VIRTUAL_PS1 _OLD_VIRTUAL_PYTHONHOME
source ${GRASPKITTOOLS}/.venv/bin/activate
cd $root/rmcdhf_test

export GRASP_BINDIR=$root/rmcdhf_test/build/bin
export GRASP_MPI_TMP=/home/workstation2/caltmp/round-guard-${SLURM_JOB_ID}
export GRASP_OMP_THREADS=1 OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
ranks=${SLURM_NTASKS:-46}
[[ $ranks == 46 ]] || { echo "ranks ($ranks) != allocated CPUs (46)" >&2; exit 2; }
test -x "$GRASP_BINDIR/rmcdhf_mpi"

out=$root/data/rmcdhf_test_data/results/round-guard-minimal-${SLURM_JOB_ID}
mkdir -p "$out"
printf 'case,runner_exit,rmcdhf_exit,convergence_exit,trace,final_csv,outcome\n' > "$out/status.csv"

common=(GRASP_ALLOW_UNBALANCED=1 \
  GRASP_TRACE_ORBOPT=1 GRASP_TRACE_INITIAL_ORBITALS=1 \
  GRASP_TRACE_RWFN=1 GRASP_ROUND_ROLLBACK_GUARD=1 \
  GRASP_ROUND_REJECT_ENERGY_ORDER=1 GRASP_MIN_STATE_OVERLAP=0.85 \
  GRASP_MAX_ROUND_ROLLBACKS=3 GRASP_STRICT_SCF=1 \
  GRASP_ALLOW_RADIAL_GRID_DIFFERENCE=1 GRASP_ALLOW_ENERGY_DIFFERENCES=1 \
  GRASP_RMCDHF_TIMEOUT=90m GRASP_ABORT_ON_ORBOPT_ERROR=1)

run_case() {
  local name=$1
  local family=$2
  local source=$3
  local previous=$4
  local isodata=$5
  local case_out=$out/$name
  local target_states=${GRASP_ROUND_TARGET_STATES:-}
  case $name in
    # Both Ni fixtures have J=0,1,2,3,4 blocks with 2,1,3,1,2 roots.
    # Their J=2,3,4 first roots are global states 4,7,8; 3,4,7 was wrong.
    # Cl I has one root per block,
    # so its two physical levels are global states 1,2.  Callers can override
    # these defaults when changing the ASF selection.
    ni_i_as2) target_states=${GRASP_ROUND_TARGET_STATES_NI_I:-4,7,8} ;;
    ni_ca_like_as2) target_states=${GRASP_ROUND_TARGET_STATES_NICA:-4,7,8} ;;
    cl_i_as1) target_states=${GRASP_ROUND_TARGET_STATES_CL_I:-1,2} ;;
  esac
  local stage=2
  local runner_exit=0
  local rmcdhf_exit=missing
  local convergence_exit=not_run
  local outcome=incomplete
  [[ $family == cl_i ]] && stage=1

  set +e
  env "${common[@]}" GRASP_PREVIOUS_WAVE="$previous" \
    GRASP_ROUND_TARGET_STATES="$target_states" \
    GRASP_ISODATA_SOURCE="$isodata" GRASP_EXPECT_RMCDHF_FAILURE=1 \
    bash test/rmcdhf_orbopt/run_data_case.sh "$family" optimized \
    "$case_out" "$ranks" estimate "$stage"
  runner_exit=$?
  set -e
  if [[ -f $case_out/rmcdhf.exitcode ]]; then
    rmcdhf_exit=$(<"$case_out/rmcdhf.exitcode")
  fi
  if [[ -f $case_out/convergence_check.exitcode ]]; then
    convergence_exit=$(<"$case_out/convergence_check.exitcode")
  fi
  local trace=false
  local final_csv=false
  [[ -s $case_out/orbopt_trace.csv ]] && trace=true
  if find "$case_out" -maxdepth 1 -type f -name '*_rmcdhf.csv' -print -quit \
      | grep -q .; then
    final_csv=true
  fi
  if [[ $rmcdhf_exit == missing ]]; then
    outcome=runner_or_setup_failed
  elif [[ $rmcdhf_exit != 0 ]]; then
    outcome=rmcdhf_failed
  elif [[ $convergence_exit == not_run ]]; then
    outcome=postprocess_failed
  elif [[ $convergence_exit != 0 ]]; then
    outcome=rmcdhf_success_strict_not_converged
  elif (( runner_exit != 0 )); then
    outcome=postprocess_failed
  elif [[ $final_csv == true ]]; then
    outcome=strict_converged
  else
    outcome=rmcdhf_success_no_final_csv
  fi
  printf '%s,%s,%s,%s,%s,%s,%s\n' "$name" "$runner_exit" "$rmcdhf_exit" \
    "$convergence_exit" "$trace" "$final_csv" "$outcome" >> "$out/status.csv"
}

run_case ni_i_as2 ni_i \
  "$external/Ni_I/e1_vv2" "$external/Ni_I/e1_vv2/e1_vv2as1.w" \
  "$external/Ni_I/e1_vv2_NV/isodata"
run_case ni_ca_like_as2 ni_ca_like \
  "$external/Ni_Ca-like/e1_cv" "$external/Ni_Ca-like/e1_cv/e1_cvas1.w" \
  "$external/Ni_Ca-like/e1_cv/isodata"
run_case cl_i_as1 cl_i \
  "$external/Cl_I/o1_cc1" "$external/Cl_I/o1_cc1/o1_cc1as0.w" \
  "$external/Cl_I/o1_cc1/isodata"

# Keep the completion marker in the same CSV while preserving its column count.
printf 'status,complete,,,,,\n' >> "$out/status.csv"
echo "results: $out"
