#!/bin/zsh
#SBATCH -J rmcdhf-ni-expected-nodes
#SBATCH -N 1
#SBATCH --ntasks-per-node=46
#SBATCH -p batch
#SBATCH --output=/home/workstation2/AppFiles/GraspKit-Workspace/data/rmcdhf_test_data/log/%j_%x.log
#SBATCH --error=/home/workstation2/AppFiles/GraspKit-Workspace/data/rmcdhf_test_data/log/%j_%x.log

# Single-factor regression for b47ac87: require each candidate to match the
# orbital's NNODEP value.  Damping, per-orbital ORTHY, and EOL weights retain
# the Job 586/587 baseline settings.
export GRASP_REJECT_NODE_CHANGE=1
unset GRASP_DEFER_ORTHY
exec zsh /home/workstation2/AppFiles/GraspKit-Workspace/rmcdhf_test/test/rmcdhf_orbopt/slurm/run_ni_as1_as2_chain_diagnostic.sbatch
