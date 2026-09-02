#!/bin/zsh
#SBATCH -J rmcdhf-b8-states
#SBATCH -N 1
#SBATCH --ntasks-per-node=1
#SBATCH -p batch
#SBATCH --output=%j_%x.log
#SBATCH --error=%j_%x.log
. /usr/share/Modules/init/zsh
set -euo pipefail
module load mpi/openmpi-x86_64
module load grasp/grasp_2990_NNNP
export GRASPKITTOOLS=/home/workstation2/AppFiles/GraspKit-Workspace/graspkit-tools
export PATH=${GRASPKITTOOLS}/scripts:${PATH}
unset VIRTUAL_ENV _OLD_VIRTUAL_PATH _OLD_VIRTUAL_PS1 _OLD_VIRTUAL_PYTHONHOME
source ${GRASPKITTOOLS}/.venv/bin/activate
root=/home/workstation2/AppFiles/GraspKit-Workspace
cd $root/rmcdhf_test
export GRASP_BINDIR=/tmp/rmcdhf-build-debug/bin
out=$root/data/rmcdhf_test_data/results/b8-state-sets-${SLURM_JOB_ID}
mkdir -p $out
run_case() {
  tag=$1; shift
  env "$@" bash test/rmcdhf_orbopt/run_data_case.sh ni_ca_like balanced "$out/$tag" 1 estimate 1
}
run_case B8_full GRASP_ORBITAL_DAMPING=-0.5 GRASP_ALLOW_RADIAL_GRID_DIFFERENCE=1
run_case B8_target_only GRASP_ORBITAL_DAMPING=-0.5 GRASP_ALLOW_RADIAL_GRID_DIFFERENCE=1 GRASP_ASF_SELECTION=$'1\n1\n1\n1\n1'
printf 'status,complete\n' > $out/status.csv
