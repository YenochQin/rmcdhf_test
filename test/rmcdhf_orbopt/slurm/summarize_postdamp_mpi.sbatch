#!/bin/zsh
#SBATCH -J summarize-postdamp-mpi
#SBATCH -N 1
#SBATCH --ntasks-per-node=1
#SBATCH -p batch
#SBATCH --output=%j_%x.log
#SBATCH --error=%j_%x.log
set -euo pipefail
: ${GRASP_RESULT_TAG:?submit with GRASP_RESULT_TAG}
root=/home/workstation2/AppFiles/GraspKit-Workspace
cd $root/rmcdhf_test
out=$root/data/rmcdhf_test_data/results/$GRASP_RESULT_TAG
python3 test/rmcdhf_orbopt/compare_guard_signatures.py \
  NP1="$out/ni_i_np1" NP2="$out/ni_i_np2" NP4="$out/ni_i_np4" \
  > "$out/ni_i_guard_repeatability.csv"
python3 test/rmcdhf_orbopt/compare_sum.py "$out/ni_ca_np1/rmcdhf.sum" \
  "$out/ni_ca_np2/rmcdhf.sum" > "$out/ni_ca_np1_np2.csv"
python3 test/rmcdhf_orbopt/compare_sum.py "$out/ni_ca_np1/rmcdhf.sum" \
  "$out/ni_ca_np4/rmcdhf.sum" > "$out/ni_ca_np1_np4.csv"
printf 'status,complete\n' > "$out/status.csv"
