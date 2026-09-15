#!/bin/zsh
# One post-implementation Ni I AS2 acceptance run.  Reuse the fixed TF/RCI
# baseline from Job 635 and Job 590's accepted balanced AS1 wavefunction.
# Do not resubmit after the fixed-reference trace and AS transaction pass.
#SBATCH -J rmcdhf-stage-guard-ni
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
export GRASP_MPI_TMP=/home/workstation2/caltmp/stage-guard-ni-${SLURM_JOB_ID}
export GRASP_OMP_THREADS=1 OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
ranks=${SLURM_NTASKS:-46}
[[ $ranks == 46 ]] || { echo "ranks ($ranks) != allocated CPUs (46)" >&2; exit 2; }
test -x "$GRASP_BINDIR/rmcdhf_mpi"

data=$root/data/rmcdhf_test_data
previous=$data/results/ni-as1-as2-chain-590/as1/e1_vv2as1.w
isodata=$data/inputs/Ni_I/e1_vv2_NV/isodata
config=$root/rmcdhf_test/test/rmcdhf_orbopt/fixtures/ni_target_acceptance.json
out=$data/results/stage-guard-ni-${SLURM_JOB_ID}
test -s "$previous" -a -s "$isodata" -a -s "$config"
rci_input=$data/results/stage-guard-ni-${SLURM_JOB_ID}-baseline-rci.stdin
printf 'y\nbaseline\ny\nn\ny\nn\nn\ny\n3\n1-2\n1\n1-3\n1\n1-2\n' > "$rci_input"

set +e
env GRASP_STAGE_TRANSACTION=1 GRASP_STAGE_CONFIG="$config" \
  GRASP_STAGE_RCI_STDIN="$rci_input" \
  GRASP_ANCHOR_TYPE=tf_baseline \
  GRASP_TRACE_ORBOPT=1 GRASP_FIXED_REFERENCE_PROXY=1 \
  GRASP_MIN_ANCHOR_SUBSPACE_PROXY=0.85 \
  GRASP_ROUND_ROLLBACK_GUARD=1 GRASP_ROUND_TARGET_STATES=5,4,3 \
  GRASP_ROUND_REJECT_ENERGY_ORDER=1 GRASP_MIN_STATE_OVERLAP=0.85 \
  GRASP_MAX_ROUND_ROLLBACKS=3 GRASP_STRICT_SCF=1 \
  GRASP_ORBITAL_DAMPING=-0.5 GRASP_NODE_GUARD_PROGRESS=1 \
  GRASP_ORBITAL_GUARD=1 GRASP_GUARD_AFTER_DAMPING=1 \
  GRASP_REJECT_NODE_CHANGE=1 GRASP_MAX_REJECTS_PER_ORBITAL=2 \
  GRASP_MIN_ORBITAL_OVERLAP=0 GRASP_MAX_RADIUS_RATIO=100 \
  GRASP_ALLOW_RADIAL_GRID_DIFFERENCE=1 GRASP_ALLOW_ENERGY_DIFFERENCES=1 \
  GRASP_ALLOW_LEVEL_DIFFERENCES=1 GRASP_RMCDHF_TIMEOUT=90m \
  GRASP_ABORT_ON_ORBOPT_ERROR=1 GRASP_PREVIOUS_WAVE="$previous" \
  GRASP_ISODATA_SOURCE="$isodata" GRASP_ASF_SELECTION=$'1\n1\n1\n1\n1' \
  bash test/rmcdhf_orbopt/run_data_case.sh ni_i balanced "$out" \
  "$ranks" estimate 2
runner_exit=$?
set -e

"$GRASPKITTOOLS/.venv/bin/python" \
  "$GRASPKITTOOLS/scripts/grasp_regular_cal/audit_stage_result.py" \
  "$out" "$runner_exit"
