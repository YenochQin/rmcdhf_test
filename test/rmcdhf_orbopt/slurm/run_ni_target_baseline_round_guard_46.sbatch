#!/bin/zsh
# Focused Ni I AS2 test: reduced-ASF EOL optimization of balanced
# relativistic orbital pairs from Job 590's AS1
# wavefunction whose 3F ordering is correct.  This answers whether state
# selection plus the round guard preserves that ordering; it does not repeat
# AS1 or the completed all-state Job 643 path.
# With one selected root in each J=0,1,2,3,4 block, the physical 3F targets
# are global roots 3,4,5 (J=2,3,4).
#SBATCH -J rmcdhf-ni-target-guard
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
export GRASPKITTOOLS=$root/graspkit-tools
export PATH=${GRASPKITTOOLS}/scripts:${PATH}
unset VIRTUAL_ENV _OLD_VIRTUAL_PATH _OLD_VIRTUAL_PS1 _OLD_VIRTUAL_PYTHONHOME
source ${GRASPKITTOOLS}/.venv/bin/activate
cd $root/rmcdhf_test

export GRASP_BINDIR=$root/rmcdhf_test/build/bin
export GRASP_MPI_TMP=/home/workstation2/caltmp/ni-target-guard-${SLURM_JOB_ID}
export GRASP_OMP_THREADS=1 OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
ranks=${SLURM_NTASKS:-46}
[[ $ranks == 46 ]] || { echo "ranks ($ranks) != allocated CPUs (46)" >&2; exit 2; }
test -x "$GRASP_BINDIR/rmcdhf_mpi"

out=$root/data/rmcdhf_test_data/results/ni-target-baseline-guard-${SLURM_JOB_ID}
previous=$root/data/rmcdhf_test_data/results/ni-as1-as2-chain-590/as1/e1_vv2as1.w
isodata=$root/data/rmcdhf_test_data/inputs/Ni_I/e1_vv2_NV/isodata
test -s "$previous" -a -s "$isodata"

set +e
env GRASP_TRACE_ORBOPT=1 GRASP_TRACE_INITIAL_ORBITALS=1 \
  GRASP_ROUND_ROLLBACK_GUARD=1 GRASP_ROUND_TARGET_STATES=3,4,5 \
  GRASP_ROUND_REJECT_ENERGY_ORDER=1 \
  GRASP_MIN_STATE_OVERLAP=0.85 GRASP_MAX_ROUND_ROLLBACKS=3 \
  GRASP_STRICT_SCF=1 GRASP_ORBITAL_DAMPING=-0.5 \
  GRASP_NODE_GUARD_PROGRESS=1 GRASP_ORBITAL_GUARD=1 \
  GRASP_GUARD_AFTER_DAMPING=1 GRASP_REJECT_NODE_CHANGE=1 \
  GRASP_MAX_REJECTS_PER_ORBITAL=2 GRASP_MIN_ORBITAL_OVERLAP=0 \
  GRASP_MAX_RADIUS_RATIO=100 GRASP_REQUIRE_BALANCED_PAIR=1 \
  GRASP_ALLOW_RADIAL_GRID_DIFFERENCE=1 \
  GRASP_ALLOW_ENERGY_DIFFERENCES=1 GRASP_ALLOW_LEVEL_DIFFERENCES=1 \
  GRASP_RMCDHF_TIMEOUT=90m GRASP_ABORT_ON_ORBOPT_ERROR=1 \
  GRASP_PREVIOUS_WAVE="$previous" GRASP_ISODATA_SOURCE="$isodata" \
  GRASP_ASF_SELECTION=$'1\n1\n1\n1\n1' \
  bash test/rmcdhf_orbopt/run_data_case.sh ni_i balanced "$out" \
  "$ranks" estimate 2
runner_exit=$?
set -e

mkdir -p "$out"
rmcdhf_exit=missing
convergence_exit=not_run
[[ -f $out/rmcdhf.exitcode ]] && rmcdhf_exit=$(<$out/rmcdhf.exitcode)
[[ -f $out/convergence_check.exitcode ]] && convergence_exit=$(<$out/convergence_check.exitcode)
printf 'runner_exit,rmcdhf_exit,convergence_exit\n%s,%s,%s\n' \
  "$runner_exit" "$rmcdhf_exit" "$convergence_exit" > $out/status.csv
exit "$runner_exit"
