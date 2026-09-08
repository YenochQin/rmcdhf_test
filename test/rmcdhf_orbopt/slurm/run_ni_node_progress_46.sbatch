#!/bin/zsh
#SBATCH -J rmcdhf-ni-node-progress
#SBATCH -N 1
#SBATCH --ntasks-per-node=46
#SBATCH -p batch
#SBATCH --output=/home/workstation2/AppFiles/GraspKit-Workspace/data/rmcdhf_test_data/log/%j_%x.log
#SBATCH --error=/home/workstation2/AppFiles/GraspKit-Workspace/data/rmcdhf_test_data/log/%j_%x.log

# Single-factor follow-up to Job 589.  The post-damping orbital may keep an
# imperfect initial node count while SCF moves it toward NNODEP, but it may
# not increase its absolute distance from NNODEP.  Damping, per-orbital
# ORTHY, EOL weights, inputs, and the 46-rank allocation remain unchanged.
export GRASP_NODE_GUARD_PROGRESS=1
export GRASP_REJECT_NODE_CHANGE=1
unset GRASP_DEFER_ORTHY
exec zsh /home/workstation2/AppFiles/GraspKit-Workspace/rmcdhf_test/test/rmcdhf_orbopt/slurm/run_ni_as1_as2_chain_diagnostic.sbatch
