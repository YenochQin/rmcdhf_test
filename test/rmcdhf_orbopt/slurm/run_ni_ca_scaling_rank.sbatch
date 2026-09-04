#!/bin/zsh
#SBATCH -J rmcdhf-ni-ca-scale
#SBATCH -N 1
#SBATCH -p batch
#SBATCH --output=%j_%x.log
#SBATCH --error=%j_%x.log
. /usr/share/Modules/init/zsh
set -euo pipefail
module load mpi/openmpi-x86_64
module load grasp/grasp_2990_NNNP
: ${GRASP_MPI_RANKS:?submit with GRASP_MPI_RANKS=12,24,or 48}
: ${GRASP_RESULT_TAG:?submit with a shared GRASP_RESULT_TAG}
if [[ $GRASP_MPI_RANKS != "$SLURM_NTASKS" ]]; then
  echo "ranks ($GRASP_MPI_RANKS) != allocated CPUs ($SLURM_NTASKS)" >&2
  exit 2
fi
root=/home/workstation2/AppFiles/GraspKit-Workspace
export GRASPKITTOOLS=$root/graspkit-tools
export PATH=${GRASPKITTOOLS}/scripts:${PATH}
unset VIRTUAL_ENV _OLD_VIRTUAL_PATH _OLD_VIRTUAL_PS1 _OLD_VIRTUAL_PYTHONHOME
source ${GRASPKITTOOLS}/.venv/bin/activate
cd $root/rmcdhf_test
export GRASP_BINDIR=/tmp/rmcdhf-build-debug/bin
export GRASP_OMP_THREADS=1 OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
ranks=$GRASP_MPI_RANKS
out=$root/data/rmcdhf_test_data/results/$GRASP_RESULT_TAG/np$ranks
mkdir -p "${out:h}"
start=$(date +%s)
env GRASP_ORBITAL_DAMPING=-0.5 GRASP_ORBITAL_GUARD=1 \
  GRASP_GUARD_AFTER_DAMPING=1 GRASP_MIN_ORBITAL_OVERLAP=0 \
  GRASP_MAX_RADIUS_RATIO=100 GRASP_REJECT_NODE_CHANGE=1 \
  GRASP_MAX_REJECTS_PER_ORBITAL=2 GRASP_ALLOW_RADIAL_GRID_DIFFERENCE=1 \
  GRASP_ABORT_ON_ORBOPT_ERROR=1 GRASP_RMCDHF_TIMEOUT=60m \
  GRASP_OMP_THREADS=1 \
  bash test/rmcdhf_orbopt/run_data_case.sh ni_ca_like balanced \
    "$out" "$ranks" estimate 2
finish=$(date +%s)
elapsed=$((finish - start))
printf 'ranks,%s\nelapsed_seconds,%s\nstatus,complete\n' \
  "$ranks" "$elapsed" > "$out/scaling_status.csv"
