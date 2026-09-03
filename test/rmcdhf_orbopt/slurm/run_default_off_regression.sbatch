#!/bin/zsh
#SBATCH -J rmcdhf-default-off
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
out=$root/data/rmcdhf_test_data/results/default-off-${SLURM_JOB_ID}
ref=$root/data/rmcdhf_test_data/results/node-stability-525
mkdir -p "$out"
for family in ni_i ni_ca_like; do
  env GRASP_ORBITAL_DAMPING=-0.5 GRASP_ALLOW_RADIAL_GRID_DIFFERENCE=1 \
    GRASP_OMP_THREADS=12 \
    bash test/rmcdhf_orbopt/run_data_case.sh "$family" balanced \
      "$out/$family" 4 estimate 2
  python3 test/rmcdhf_orbopt/compare_sum.py "$out/$family/rmcdhf.sum" \
    "$ref/${family/ni_ca_like/ni_ca_like}_as2_damp_0.5/rmcdhf.sum" \
    > "$out/$family/default_off_comparison.csv"
done
printf 'status,complete\n' > "$out/status.csv"
