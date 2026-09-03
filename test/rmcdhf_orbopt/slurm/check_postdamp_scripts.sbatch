#!/bin/zsh
#SBATCH -J rmcdhf-postdamp-check
#SBATCH -N 1
#SBATCH --ntasks-per-node=1
#SBATCH -p batch
#SBATCH --output=%j_%x.log
#SBATCH --error=%j_%x.log
set -euo pipefail
root=/home/workstation2/AppFiles/GraspKit-Workspace
zsh -n "$root/rmcdhf_test/test/rmcdhf_orbopt/slurm/run_postdamp_guard_matrix.sbatch"
bash -n "$root/rmcdhf_test/test/rmcdhf_orbopt/run_data_case.sh"
python3 -m py_compile "$root/rmcdhf_test/test/rmcdhf_orbopt/validate_postdamp_guard.py"
printf 'status,pass\n'
