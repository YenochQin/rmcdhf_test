#!/bin/zsh
#SBATCH -J rmcdhf-node-recovery
#SBATCH -N 1
#SBATCH --ntasks-per-node=1
#SBATCH -p batch
#SBATCH --output=%j_%x.log
#SBATCH --error=%j_%x.log
set -euo pipefail
root=/home/workstation2/AppFiles/GraspKit-Workspace
src=$root/data/rmcdhf_test_data/results/node-stability-525
out=$root/data/rmcdhf_test_data/results/node-recovery-${SLURM_JOB_ID}
analyzer=$root/rmcdhf_test/test/rmcdhf_orbopt/analyze_damped_node_recovery.py
mkdir -p "$out"
for damp in 0.2 0.5 0.8; do
  python3 "$analyzer" "$src/ni_i_as2_damp_${damp}/orbopt_trace.csv" \
    > "$out/ni_i_damp_${damp}.csv"
done
printf 'status,complete\n' > "$out/status.csv"
