#!/bin/zsh
#SBATCH -J rmcdhf-postdamp-rank
#SBATCH -N 1
#SBATCH -p batch
#SBATCH --output=%j_%x.log
#SBATCH --error=%j_%x.log
. /usr/share/Modules/init/zsh
set -euo pipefail
module load mpi/openmpi-x86_64
module load grasp/grasp_2990_NNNP
: ${GRASP_MPI_RANKS:?submit with GRASP_MPI_RANKS=1,2,or 4}
: ${GRASP_RESULT_TAG:?submit with a shared GRASP_RESULT_TAG}
if [[ $GRASP_MPI_RANKS != "$SLURM_NTASKS" ]]; then
  echo "requested ranks ($GRASP_MPI_RANKS) != allocated CPUs ($SLURM_NTASKS)" >&2
  exit 2
fi
root=/home/workstation2/AppFiles/GraspKit-Workspace
export GRASPKITTOOLS=$root/graspkit-tools
export PATH=${GRASPKITTOOLS}/scripts:${PATH}
unset VIRTUAL_ENV _OLD_VIRTUAL_PATH _OLD_VIRTUAL_PS1 _OLD_VIRTUAL_PYTHONHOME
source ${GRASPKITTOOLS}/.venv/bin/activate
cd $root/rmcdhf_test
export GRASP_BINDIR=/tmp/rmcdhf-build-debug/bin
export GRASP_OMP_THREADS=1
out=$root/data/rmcdhf_test_data/results/$GRASP_RESULT_TAG
mkdir -p "$out"
ranks=$GRASP_MPI_RANKS
common=(
  GRASP_ORBITAL_DAMPING=-0.5 GRASP_ORBITAL_GUARD=1
  GRASP_GUARD_AFTER_DAMPING=1 GRASP_MIN_ORBITAL_OVERLAP=0
  GRASP_MAX_RADIUS_RATIO=100 GRASP_REJECT_NODE_CHANGE=1
  GRASP_MAX_REJECTS_PER_ORBITAL=2 GRASP_ALLOW_RADIAL_GRID_DIFFERENCE=1
  GRASP_ABORT_ON_ORBOPT_ERROR=1 GRASP_RMCDHF_TIMEOUT=30m
  GRASP_OMP_THREADS=1
)
env "${common[@]}" GRASP_EXPECT_RMCDHF_FAILURE=1 \
  bash test/rmcdhf_orbopt/run_data_case.sh ni_i balanced \
    "$out/ni_i_np$ranks" "$ranks" estimate 2
env "${common[@]}" \
  bash test/rmcdhf_orbopt/run_data_case.sh ni_ca_like balanced \
    "$out/ni_ca_np$ranks" "$ranks" estimate 2
printf 'ranks,%s\nstatus,complete\n' "$ranks" > "$out/np${ranks}_status.csv"
