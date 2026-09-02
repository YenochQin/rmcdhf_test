#!/bin/zsh
#SBATCH -J rmcdhf-cl-chain
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
export GRASP_OMP_THREADS=12
out=$root/data/rmcdhf_test_data/results/cl-as-chain-${SLURM_JOB_ID}
mkdir -p $out
previous=$root/data/rmcdhf_test_data/results/recovered_20260831/tmp/rmcdhf-damping-20260825/cl_as1_damp_05/rwfn.out
for stage in 2 3 4 5; do
  tag=cl_as${stage}_balanced_damped
  env GRASP_ORBITAL_DAMPING=-0.5 GRASP_ALLOW_RADIAL_GRID_DIFFERENCE=1 \
    GRASP_PREVIOUS_WAVE="$previous" \
    bash test/rmcdhf_orbopt/run_data_case.sh cl_i balanced "$out/$tag" 4 estimate "$stage"
  previous=$out/$tag/rwfn.out
done
printf 'status,complete\n' > "$out/status.csv"
