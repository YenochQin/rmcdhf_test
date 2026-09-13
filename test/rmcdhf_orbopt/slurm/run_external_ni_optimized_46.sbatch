#!/bin/zsh
# External NVMe Ni I optimized pair, AS1 -> AS2.
# Use the Job 608 build; the later sparse-index build failed physical validation.
#SBATCH -J rmcdhf-ext-ni-opt
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
export GRASP_ISODATA_SOURCE=$external/Ni_I/e1_vv2_NV/isodata
export PATH=${GRASPKITTOOLS}/scripts:${PATH}
unset VIRTUAL_ENV _OLD_VIRTUAL_PATH _OLD_VIRTUAL_PS1 _OLD_VIRTUAL_PYTHONHOME
unset GRASP_ORBITAL_DAMPING GRASP_ORBITAL_GUARD GRASP_GUARD_AFTER_DAMPING \
  GRASP_REJECT_NODE_CHANGE GRASP_NODE_GUARD_PROGRESS GRASP_REQUIRE_BALANCED_PAIR
source ${GRASPKITTOOLS}/.venv/bin/activate
cd $root/rmcdhf_test

# Job 608 binary: QDIF + Gatherv, without the Job 609 sparse-index regression.
unset GRASP_RMCDHF_MPI_BINDIR
export GRASP_BINDIR=$root/rmcdhf_test/build-gatherv/bin
export GRASP_MPI_TMP=/home/workstation2/caltmp/external-${SLURM_JOB_ID}
export GRASP_OMP_THREADS=1 OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
ranks=${SLURM_NTASKS:-46}
[[ $ranks == 46 ]] || { echo "ranks ($ranks) != allocated CPUs (46)" >&2; exit 2; }
test -x "$GRASP_BINDIR/rmcdhf_mpi"

out=$root/data/rmcdhf_test_data/results/external-ni-optimized-${SLURM_JOB_ID}
mkdir -p "$out"
# Preserve the failure stage even when the runner exits before post-processing.
stage=as1
TRAPEXIT() {
  local result=$?
  if (( result != 0 )); then
    printf 'status,failed\nstage,%s\nexitcode,%s\n' "$stage" "$result" > "$out/status.csv"
  fi
}
printf 'binary,%s\n' "$GRASP_BINDIR/rmcdhf_mpi" > "$out/run_manifest.txt"
sha256sum "$GRASP_BINDIR/rmcdhf_mpi" >> "$out/run_manifest.txt"
common=(GRASP_TRACE_ORBOPT=1 GRASP_TRACE_INITIAL_ORBITALS=1 \
  GRASP_TRACE_RWFN=1 GRASP_ALLOW_RADIAL_GRID_DIFFERENCE=1 \
  GRASP_ALLOW_ENERGY_DIFFERENCES=1 \
  GRASP_RMCDHF_TIMEOUT=60m \
  GRASP_ABORT_ON_ORBOPT_ERROR=1)
env "${common[@]}" bash test/rmcdhf_orbopt/run_data_case.sh \
  ni_i optimized "$out/as1" "$ranks" estimate 1
as1_wave=$out/as1/e1_vv2as1.w
test -s "$as1_wave"
stage=as2
env "${common[@]}" GRASP_PREVIOUS_WAVE="$as1_wave" \
  bash test/rmcdhf_orbopt/run_data_case.sh \
  ni_i optimized "$out/as2" "$ranks" estimate 2
printf 'status,complete\n' > "$out/status.csv"
