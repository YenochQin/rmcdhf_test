#!/bin/zsh
#SBATCH -J summarize-ni-ca-scale
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
for ranks in 12 24 48; do
  cat "$out/np$ranks/scaling_status.csv"
done > "$out/scaling_summary.csv"
python3 test/rmcdhf_orbopt/compare_sum.py "$out/np12/rmcdhf.sum" \
  "$out/np24/rmcdhf.sum" > "$out/np12_np24.csv"
python3 test/rmcdhf_orbopt/compare_sum.py "$out/np12/rmcdhf.sum" \
  "$out/np48/rmcdhf.sum" > "$out/np12_np48.csv"
printf 'status,complete\n' > "$out/status.csv"
