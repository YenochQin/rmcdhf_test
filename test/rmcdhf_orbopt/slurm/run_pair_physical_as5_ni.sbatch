#!/bin/zsh
# Continue the accepted Ni I AS4 (r1 Job 716; r2 Job 718 is bitwise identical) into AS5.
# Ni I's target chain runs through AS5 (max_stage=5); this is the final layer.
# GRASP_* settings match the AS4 rerun (GRASP_RMCDHF_TIMEOUT unset, iteration limit 200;
# AS5 has ~229k CSFs). The strict convergence gate is unchanged.
# This is a physical acceptance probe: no fallback output is credited.
# Submit with sbatch; do not invoke run_data_case.sh directly for this test.
#SBATCH -J rmcdhf-pair-physical-as5-ni
#SBATCH -N 1
#SBATCH --ntasks-per-node=46
#SBATCH --cpus-per-task=1
#SBATCH -p batch
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
export GRASP_MPI_TMP=/home/workstation2/caltmp/pair-physical-as5-ni-${SLURM_JOB_ID}
export GRASP_OMP_THREADS=1 OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
export GRASP_PAIR_TRANSACTION=1 GRASP_REQUIRE_BALANCED_PAIR=1
export GRASP_MAX_PAIR_RETRIES=3
export GRASP_TRACE_ORBOPT=1 GRASP_FIXED_REFERENCE_PROXY=1
export GRASP_ROUND_ROLLBACK_GUARD=1 GRASP_ROUND_TARGET_STATES=5,4,3
export GRASP_ROUND_REJECT_ENERGY_ORDER=1 GRASP_MIN_STATE_OVERLAP=0.85
export GRASP_MAX_ROUND_ROLLBACKS=3 GRASP_STRICT_SCF=1
export GRASP_ORBITAL_DAMPING=-0.5 GRASP_NODE_GUARD_PROGRESS=1
export GRASP_ORBITAL_GUARD=1 GRASP_GUARD_AFTER_DAMPING=1
export GRASP_REJECT_NODE_CHANGE=1 GRASP_MAX_REJECTS_PER_ORBITAL=2
export GRASP_MIN_ORBITAL_OVERLAP=0 GRASP_MAX_RADIUS_RATIO=100
export GRASP_ALLOW_RADIAL_GRID_DIFFERENCE=1
export GRASP_RMCDHF_MAX_ITERATIONS=200

data=$root/data/rmcdhf_test_data
previous=$data/results/pair-physical-as4-ni-716/e1_vv2as4.w
test -s "$previous"
test -x "$GRASP_BINDIR/rmcdhf_mpi"
sha256sum "$GRASP_BINDIR/rmcdhf_mpi"

out=$data/results/pair-physical-as5-ni-${SLURM_JOB_ID}
GRASP_PREVIOUS_WAVE=$previous \
  bash test/rmcdhf_orbopt/run_data_case.sh ni_i balanced "$out" \
  "${SLURM_NTASKS:-46}" estimate 5

printf 'status,complete\n' > "$out/sbatch_status.csv"
