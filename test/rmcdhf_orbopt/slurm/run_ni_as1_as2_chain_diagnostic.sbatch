#!/bin/zsh
#SBATCH -J rmcdhf-ni-as-chain
#SBATCH -N 1
#SBATCH --ntasks-per-node=12
#SBATCH -p batch
#SBATCH --output=%j_%x.log
#SBATCH --error=%j_%x.log
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
export GRASP_BINDIR=/tmp/rmcdhf-build-debug/bin
export GRASP_OMP_THREADS=1 OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
out=$root/data/rmcdhf_test_data/results/ni-as1-as2-chain-${SLURM_JOB_ID}
mkdir -p "${out:h}"
common=(GRASP_TRACE_ORBOPT=1 GRASP_ORBITAL_DAMPING=-0.5 \
  GRASP_ALLOW_RADIAL_GRID_DIFFERENCE=1 GRASP_RMCDHF_TIMEOUT=30m \
  GRASP_OMP_THREADS=1)
env "${common[@]}" GRASP_ORBITAL_GUARD=1 GRASP_GUARD_AFTER_DAMPING=1 \
  GRASP_MIN_ORBITAL_OVERLAP=0 GRASP_MAX_RADIUS_RATIO=100 \
  GRASP_REJECT_NODE_CHANGE=1 GRASP_MAX_REJECTS_PER_ORBITAL=2 \
  GRASP_ABORT_ON_ORBOPT_ERROR=1 \
  bash test/rmcdhf_orbopt/run_data_case.sh ni_i balanced "$out/as1" 12 estimate 1
env "${common[@]}" GRASP_ORBITAL_GUARD=1 GRASP_GUARD_AFTER_DAMPING=1 \
  GRASP_MIN_ORBITAL_OVERLAP=0 GRASP_MAX_RADIUS_RATIO=100 \
  GRASP_REJECT_NODE_CHANGE=1 GRASP_MAX_REJECTS_PER_ORBITAL=2 \
  GRASP_ABORT_ON_ORBOPT_ERROR=1 GRASP_EXPECT_RMCDHF_FAILURE=1 \
  GRASP_PREVIOUS_WAVE="$out/as1/rwfn.out" \
  bash test/rmcdhf_orbopt/run_data_case.sh ni_i balanced "$out/as2" 12 estimate 2
printf 'status,complete\n' > "$out/status.csv"
