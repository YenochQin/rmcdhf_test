#!/bin/zsh
#SBATCH -J rmcdhf-postdamp-mpi
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
out=$root/data/rmcdhf_test_data/results/postdamp-mpi-${SLURM_JOB_ID}
mkdir -p "$out"
for ranks in 1 2 4; do
  threads=$((48 / ranks))
  env GRASP_ORBITAL_DAMPING=-0.5 GRASP_ORBITAL_GUARD=1 \
    GRASP_GUARD_AFTER_DAMPING=1 GRASP_MIN_ORBITAL_OVERLAP=0 \
    GRASP_MAX_RADIUS_RATIO=100 GRASP_REJECT_NODE_CHANGE=1 \
    GRASP_MAX_REJECTS_PER_ORBITAL=2 GRASP_ALLOW_RADIAL_GRID_DIFFERENCE=1 \
    GRASP_EXPECT_RMCDHF_FAILURE=1 GRASP_ABORT_ON_ORBOPT_ERROR=1 \
    GRASP_RMCDHF_TIMEOUT=30m GRASP_OMP_THREADS="$threads" \
    bash test/rmcdhf_orbopt/run_data_case.sh ni_i balanced \
      "$out/ni_i_np$ranks" "$ranks" estimate 2
  env GRASP_ORBITAL_DAMPING=-0.5 GRASP_ORBITAL_GUARD=1 \
    GRASP_GUARD_AFTER_DAMPING=1 GRASP_MIN_ORBITAL_OVERLAP=0 \
    GRASP_MAX_RADIUS_RATIO=100 GRASP_REJECT_NODE_CHANGE=1 \
    GRASP_MAX_REJECTS_PER_ORBITAL=2 GRASP_ALLOW_RADIAL_GRID_DIFFERENCE=1 \
    GRASP_ABORT_ON_ORBOPT_ERROR=1 GRASP_RMCDHF_TIMEOUT=30m \
    GRASP_OMP_THREADS="$threads" \
    bash test/rmcdhf_orbopt/run_data_case.sh ni_ca_like balanced \
      "$out/ni_ca_np$ranks" "$ranks" estimate 2
done
python3 test/rmcdhf_orbopt/compare_guard_signatures.py \
  NP1="$out/ni_i_np1" NP2="$out/ni_i_np2" NP4="$out/ni_i_np4" \
  > "$out/ni_i_guard_repeatability.csv"
python3 test/rmcdhf_orbopt/compare_sum.py "$out/ni_ca_np1/rmcdhf.sum" \
  "$out/ni_ca_np2/rmcdhf.sum" > "$out/ni_ca_np1_np2.csv"
python3 test/rmcdhf_orbopt/compare_sum.py "$out/ni_ca_np1/rmcdhf.sum" \
  "$out/ni_ca_np4/rmcdhf.sum" > "$out/ni_ca_np1_np4.csv"
printf 'status,complete\n' > "$out/status.csv"
