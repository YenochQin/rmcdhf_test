#!/bin/zsh
# External NVMe Ni I no-varied pair, AS1 -> AS2.
#SBATCH -J rmcdhf-ext-ni-nv
#SBATCH -N 1
#SBATCH --ntasks-per-node=46
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
unset GRASP_ORBITAL_DAMPING GRASP_ORBITAL_GUARD GRASP_GUARD_AFTER_DAMPING \
  GRASP_REJECT_NODE_CHANGE GRASP_NODE_GUARD_PROGRESS GRASP_REQUIRE_BALANCED_PAIR
source ${GRASPKITTOOLS}/.venv/bin/activate
cd $root/rmcdhf_test

export GRASP_BINDIR=$root/rmcdhf_test/build/bin
export GRASP_MPI_TMP=/home/workstation2/caltmp
export GRASP_OMP_THREADS=1 OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
ranks=${SLURM_NTASKS:-46}
[[ $ranks == 46 ]] || { echo "ranks ($ranks) != allocated CPUs (46)" >&2; exit 2; }
test -x "$GRASP_BINDIR/rmcdhf_mpi"

out=$root/data/rmcdhf_test_data/results/external-ni-nv-${SLURM_JOB_ID}
mkdir -p "$out"
common=(GRASP_TRACE_ORBOPT=1 GRASP_TRACE_INITIAL_ORBITALS=1 \
  GRASP_TRACE_RWFN=1 GRASP_ALLOW_RADIAL_GRID_DIFFERENCE=1 \
  GRASP_RMCDHF_TIMEOUT=60m \
  GRASP_ABORT_ON_ORBOPT_ERROR=1)
env "${common[@]}" bash test/rmcdhf_orbopt/run_data_case.sh \
  ni_i nv "$out/as1" "$ranks" estimate 1
as1_wave=$out/as1/e1_vv2_NVas1.w
test -s "$as1_wave"
env "${common[@]}" GRASP_PREVIOUS_WAVE="$as1_wave" \
  bash test/rmcdhf_orbopt/run_data_case.sh \
  ni_i nv "$out/as2" "$ranks" estimate 2
printf 'status,complete\n' > "$out/status.csv"
