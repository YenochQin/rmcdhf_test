#!/bin/zsh
# One-case validation of target-column CI overlap matching.
# Job 643 completed the initial-CI production check.  Reuse this script only
# for a deliberate follow-up (for example accepted-root-swap validation); do
# not resubmit it as a generic regression.
#SBATCH -J rmcdhf-round-target-ni
#SBATCH -N 1
#SBATCH --ntasks-per-node=46
#SBATCH --cpus-per-task=1
#SBATCH -p batch
#SBATCH --time=02:00:00
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
export GRASP_MPI_TMP=/home/workstation2/caltmp/round-target-column-${SLURM_JOB_ID}
export GRASP_OMP_THREADS=1 OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
ranks=${SLURM_NTASKS:-46}
[[ $ranks == 46 ]] || { echo "ranks ($ranks) != allocated CPUs (46)" >&2; exit 2; }
test -x "$GRASP_BINDIR/rmcdhf_mpi"

out=$root/data/rmcdhf_test_data/results/round-target-column-ni-${SLURM_JOB_ID}
previous=$external/Ni_I/e1_vv2/e1_vv2as1.w
isodata=$external/Ni_I/e1_vv2_NV/isodata
test -s "$previous" -a -s "$isodata"

set +e
env GRASP_TRACE_ORBOPT=1 GRASP_TRACE_INITIAL_ORBITALS=1 \
  GRASP_TRACE_RWFN=1 GRASP_ROUND_ROLLBACK_GUARD=1 \
  GRASP_ROUND_REJECT_ENERGY_ORDER=1 GRASP_ROUND_TARGET_STATES=4,7,8 \
  GRASP_MIN_STATE_OVERLAP=0.85 GRASP_MAX_ROUND_ROLLBACKS=3 \
  GRASP_STRICT_SCF=1 GRASP_ALLOW_RADIAL_GRID_DIFFERENCE=1 \
  GRASP_ALLOW_ENERGY_DIFFERENCES=1 GRASP_RMCDHF_TIMEOUT=90m \
  GRASP_ABORT_ON_ORBOPT_ERROR=1 GRASP_EXPECT_RMCDHF_FAILURE=1 \
  GRASP_PREVIOUS_WAVE="$previous" GRASP_ISODATA_SOURCE="$isodata" \
  bash test/rmcdhf_orbopt/run_data_case.sh ni_i optimized "$out" \
  "$ranks" estimate 2
runner_exit=$?
set -e

# run_data_case.sh creates the case directory itself and rejects an existing
# directory to prevent accidental overwrite.  Create it only after the run
# when recording status, including the setup-failure path.
mkdir -p "$out"
rmcdhf_exit=missing
convergence_exit=not_run
[[ -f $out/rmcdhf.exitcode ]] && rmcdhf_exit=$(<$out/rmcdhf.exitcode)
[[ -f $out/convergence_check.exitcode ]] && convergence_exit=$(<$out/convergence_check.exitcode)
printf 'runner_exit,rmcdhf_exit,convergence_exit\n%s,%s,%s\n' \
  "$runner_exit" "$rmcdhf_exit" "$convergence_exit" > "$out/status.csv"
printf 'status,complete\n'
