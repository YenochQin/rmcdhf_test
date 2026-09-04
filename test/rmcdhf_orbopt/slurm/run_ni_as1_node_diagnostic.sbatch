#!/bin/zsh
#SBATCH -J rmcdhf-ni-as1-diag
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
out=$root/data/rmcdhf_test_data/results/ni-as1-diagnostic-${SLURM_JOB_ID}
mkdir -p "${out:h}"
run_case() {
  tag=$1; mode=$2; extra=$3
  set +e
  env GRASP_TRACE_ORBOPT=1 GRASP_ORBITAL_DAMPING=-0.5 \
    GRASP_ALLOW_RADIAL_GRID_DIFFERENCE=1 GRASP_RMCDHF_TIMEOUT=20m \
    GRASP_ABORT_ON_ORBOPT_ERROR=1 GRASP_OMP_THREADS=1 $extra \
    bash test/rmcdhf_orbopt/run_data_case.sh ni_i "$mode" "$out/$tag" 12 estimate 1
  rc=$?
  set -e
  printf '%s,%s\n' "$tag" "$rc" >> "$out/exitcodes.csv"
}
run_case nv nv ''
run_case balanced balanced 'GRASP_ORBITAL_GUARD=1 GRASP_GUARD_AFTER_DAMPING=0 GRASP_MIN_ORBITAL_OVERLAP=0 GRASP_MAX_RADIUS_RATIO=100 GRASP_REJECT_NODE_CHANGE=1 GRASP_MAX_REJECTS_PER_ORBITAL=2 GRASP_EXPECT_RMCDHF_FAILURE=1'
run_case postdamp balanced 'GRASP_ORBITAL_GUARD=1 GRASP_GUARD_AFTER_DAMPING=1 GRASP_MIN_ORBITAL_OVERLAP=0 GRASP_MAX_RADIUS_RATIO=100 GRASP_REJECT_NODE_CHANGE=1 GRASP_MAX_REJECTS_PER_ORBITAL=2 GRASP_EXPECT_RMCDHF_FAILURE=1'
printf 'status,complete\n' > "$out/status.csv"
