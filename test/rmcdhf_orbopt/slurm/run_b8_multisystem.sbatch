#!/bin/zsh
#SBATCH -J rmcdhf-b8-multi
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
out=$root/data/rmcdhf_test_data/results/b8-multisystem-${SLURM_JOB_ID}
mkdir -p $out
run_case() {
  tag=$1; family=$2; selection=$3
  env GRASP_ORBITAL_DAMPING=-0.5 GRASP_ALLOW_RADIAL_GRID_DIFFERENCE=1 GRASP_ALLOW_LEVEL_DIFFERENCES=1 GRASP_ASF_SELECTION="$selection" \
    bash test/rmcdhf_orbopt/run_data_case.sh "$family" balanced "$out/$tag" 1 estimate 2
}
full=$'1-2\n1\n1-3\n1\n1-2'
target=$'1\n1\n1\n1\n1'
run_case ni_i_as2_full ni_i "$full"
run_case ni_i_as2_target_only ni_i "$target"
run_case ni_ca_as2_full ni_ca_like "$full"
run_case ni_ca_as2_target_only ni_ca_like "$target"
printf 'status,complete\n' > $out/status.csv
