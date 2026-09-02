#!/bin/zsh
#SBATCH -J rmcdhf-guard-tests
#SBATCH -N 1
#SBATCH --ntasks-per-node=1
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
out=$root/data/rmcdhf_test_data/results/guard-tests-${SLURM_JOB_ID}
mkdir -p $out
run_case() {
  tag=$1; family=$2; shift 2
  set +e
  env GRASP_ORBITAL_DAMPING=-0.5 GRASP_ORBITAL_GUARD=1 GRASP_MAX_REJECTS_PER_ORBITAL=2 \
    GRASP_ALLOW_RADIAL_GRID_DIFFERENCE=1 GRASP_EXPECT_RMCDHF_FAILURE=1 \
    bash test/rmcdhf_orbopt/run_data_case.sh "$family" balanced "$out/$tag" 1 estimate 2 "$@"
  rc=$?
  set -e
  printf '%s,%s\n' "$tag" "$rc" >> "$out/guard_exitcodes.csv"
}
run_case ni_i_as2_guard ni_i
run_case ni_ca_like_as2_guard ni_ca_like
printf 'status,complete\n' > $out/status.csv
