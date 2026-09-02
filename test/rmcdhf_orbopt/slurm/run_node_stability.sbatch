#!/bin/zsh
#SBATCH -J rmcdhf-node-stability
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
out=$root/data/rmcdhf_test_data/results/node-stability-${SLURM_JOB_ID}
mkdir -p $out
for family in ni_i ni_ca_like; do
  for damp in -0.2 -0.5 -0.8; do
    tag=${family}_as2_damp_${damp#-}
    env GRASP_ORBITAL_DAMPING=$damp GRASP_ALLOW_RADIAL_GRID_DIFFERENCE=1 \
      bash test/rmcdhf_orbopt/run_data_case.sh "$family" balanced "$out/$tag" 1 estimate 2
  done
done
printf 'status,complete\n' > $out/status.csv
