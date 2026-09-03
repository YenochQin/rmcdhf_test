#!/bin/zsh
#SBATCH -J rmcdhf-postdamp-48mpi
#SBATCH -N 1
#SBATCH --ntasks-per-node=48
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
export GRASP_OMP_THREADS=1
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
out=$root/data/rmcdhf_test_data/results/postdamp-48mpi-${SLURM_JOB_ID}
mkdir -p "$out"
common=(
  GRASP_ORBITAL_GUARD=1 GRASP_GUARD_AFTER_DAMPING=1
  GRASP_MIN_ORBITAL_OVERLAP=0 GRASP_MAX_RADIUS_RATIO=100
  GRASP_REJECT_NODE_CHANGE=1 GRASP_MAX_REJECTS_PER_ORBITAL=2
  GRASP_ALLOW_RADIAL_GRID_DIFFERENCE=1 GRASP_ABORT_ON_ORBOPT_ERROR=1
  GRASP_RMCDHF_TIMEOUT=30m GRASP_OMP_THREADS=1
)
run_expected_failure() {
  tag=$1; damping=$2
  env "${common[@]}" GRASP_ORBITAL_DAMPING="$damping" \
    GRASP_EXPECT_RMCDHF_FAILURE=1 \
    bash test/rmcdhf_orbopt/run_data_case.sh ni_i balanced \
      "$out/$tag" 48 estimate 2
  read -r code < "$out/$tag/rmcdhf.exitcode"
  printf '%s,%s\n' "$tag" "$code" >> "$out/rmcdhf_exitcodes.csv"
}
run_expected_failure ni_i_postdamp_05 -0.5
run_expected_failure ni_i_postdamp_08 -0.8
env "${common[@]}" GRASP_ORBITAL_DAMPING=-0.5 \
  bash test/rmcdhf_orbopt/run_data_case.sh ni_ca_like balanced \
    "$out/ni_ca_postdamp_05" 48 estimate 2
read -r code < "$out/ni_ca_postdamp_05/rmcdhf.exitcode"
printf '%s,%s\n' ni_ca_postdamp_05 "$code" >> "$out/rmcdhf_exitcodes.csv"
printf 'status,complete\n' > "$out/status.csv"
