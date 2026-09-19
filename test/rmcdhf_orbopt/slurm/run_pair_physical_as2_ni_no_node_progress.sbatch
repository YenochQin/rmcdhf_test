#!/bin/zsh
# Diagnose Job 647 by disabling only the nodes_progress gate.
# A converged result is diagnostic and is not production-acceptable by itself.
#SBATCH -J rmcdhf-pair-as2-ni-no-node
#SBATCH -N 1
#SBATCH --ntasks-per-node=4
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
export GRASP_MPI_TMP=/home/workstation2/caltmp/pair-as2-ni-no-node-${SLURM_JOB_ID}
export GRASP_OMP_THREADS=1 OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
export GRASP_PAIR_TRANSACTION=1 GRASP_REQUIRE_BALANCED_PAIR=1
export GRASP_MAX_PAIR_RETRIES=3
export GRASP_TRACE_ORBOPT=1 GRASP_FIXED_REFERENCE_PROXY=1
export GRASP_ROUND_ROLLBACK_GUARD=1 GRASP_ROUND_TARGET_STATES=5,4,3
export GRASP_ROUND_REJECT_ENERGY_ORDER=1 GRASP_MIN_STATE_OVERLAP=0.85
export GRASP_MAX_ROUND_ROLLBACKS=3 GRASP_STRICT_SCF=1
export GRASP_ORBITAL_DAMPING=-0.5
unset GRASP_NODE_GUARD_PROGRESS
export GRASP_ORBITAL_GUARD=1 GRASP_GUARD_AFTER_DAMPING=1
export GRASP_REJECT_NODE_CHANGE=1 GRASP_MAX_REJECTS_PER_ORBITAL=2
export GRASP_MIN_ORBITAL_OVERLAP=0 GRASP_MAX_RADIUS_RATIO=100
export GRASP_ALLOW_RADIAL_GRID_DIFFERENCE=1
export GRASP_RMCDHF_TIMEOUT=90m

data=$root/data/rmcdhf_test_data
previous=$data/results/pair-strict-as1-ni-r1-20260916013000/e1_vv2as1.w
test -s "$previous"
test -x "$GRASP_BINDIR/rmcdhf_mpi"

out=$data/results/pair-physical-as2-ni-no-node-${SLURM_JOB_ID}
GRASP_PREVIOUS_WAVE=$previous \
  bash test/rmcdhf_orbopt/run_data_case.sh ni_i balanced "$out" \
  "${SLURM_NTASKS:-4}" estimate 2

printf 'status,diagnostic_complete\n' > "$out/sbatch_status.csv"
