#!/bin/zsh
# Default-branch regression: complete Cl I AS1--AS5 chain.
#SBATCH -J rmcdhf-default-cl
#SBATCH -N 1
#SBATCH --ntasks-per-node=46
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
export GRASP_MPI_TMP=/home/workstation2/caltmp
export GRASP_OMP_THREADS=1 OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
ranks=${SLURM_NTASKS:-46}
[[ $ranks == 46 ]] || { echo "ranks ($ranks) != allocated CPUs (46)" >&2; exit 2; }
test -x $GRASP_BINDIR/rmcdhf_mpi

unset GRASP_NODE_GUARD_PROGRESS
out=$root/data/rmcdhf_test_data/results/default-off-cl-chain-${SLURM_JOB_ID}
mkdir -p $out
previous=
for stage in 1 2 3 4 5; do
  stage_out=$out/as${stage}
  common=(GRASP_TRACE_ORBOPT=1 GRASP_TRACE_INITIAL_ORBITALS=1 \
    GRASP_ORBITAL_DAMPING=-0.5 GRASP_ORBITAL_GUARD=1 \
    GRASP_GUARD_AFTER_DAMPING=1 GRASP_REJECT_NODE_CHANGE=1 \
    GRASP_MAX_REJECTS_PER_ORBITAL=2 GRASP_MIN_ORBITAL_OVERLAP=0 \
    GRASP_MAX_RADIUS_RATIO=100 GRASP_ALLOW_RADIAL_GRID_DIFFERENCE=1 \
    GRASP_RMCDHF_TIMEOUT=30m GRASP_ABORT_ON_ORBOPT_ERROR=1 \
    GRASP_REQUIRE_BALANCED_PAIR=1)
  if [[ -n $previous ]]; then
    env "${common[@]}" GRASP_PREVIOUS_WAVE=$previous \
      bash test/rmcdhf_orbopt/run_data_case.sh cl_i balanced \
      $stage_out $ranks estimate $stage
  else
    env "${common[@]}" bash test/rmcdhf_orbopt/run_data_case.sh cl_i balanced \
      $stage_out $ranks estimate $stage
  fi
  previous=$stage_out/rwfn.out
done
printf 'status,complete\n' > $out/status.csv
