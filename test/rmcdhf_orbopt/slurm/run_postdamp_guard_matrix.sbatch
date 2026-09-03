#!/bin/zsh
#SBATCH -J rmcdhf-postdamp
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
out=$root/data/rmcdhf_test_data/results/postdamp-guard-${SLURM_JOB_ID}
mkdir -p "$out"
runner=test/rmcdhf_orbopt/run_data_case.sh
validate=$root/rmcdhf_test/test/rmcdhf_orbopt/validate_postdamp_guard.py

run_case() {
  tag=$1; family=$2; damping=$3; guard_mode=$4
  env GRASP_ORBITAL_DAMPING="$damping" GRASP_ORBITAL_GUARD=1 \
    GRASP_GUARD_AFTER_DAMPING="$guard_mode" GRASP_MIN_ORBITAL_OVERLAP=0 \
    GRASP_MAX_RADIUS_RATIO=100 GRASP_REJECT_NODE_CHANGE=1 \
    GRASP_MAX_REJECTS_PER_ORBITAL=2 GRASP_ALLOW_RADIAL_GRID_DIFFERENCE=1 \
    GRASP_OMP_THREADS=12 GRASP_RMCDHF_TIMEOUT=30m \
    bash "$runner" "$family" balanced "$out/$tag" 4 estimate 2
  python3 "$validate" "$out/$tag/orbopt_trace.csv" > "$out/$tag/guard_validation.csv"
}

# The executable must advertise the experimental control before calculations;
# this prevents silently running the historical pre-damping guard path.
if ! strings /tmp/rmcdhf-build-debug/bin/rmcdhf_mpi | grep -q GRASP_GUARD_AFTER_DAMPING; then
  echo 'missing GRASP_GUARD_AFTER_DAMPING in rmcdhf_mpi; implement the experimental path first' >&2
  exit 2
fi
run_case ni_i_postdamp_05 ni_i -0.5 1
run_case ni_i_postdamp_08 ni_i -0.8 1
run_case ni_ca_postdamp_05 ni_ca_like -0.5 1
run_case ni_i_predamp_05 ni_i -0.5 0
printf 'status,complete\n' > "$out/status.csv"
