#!/bin/zsh
#SBATCH -J rmcdhf-ni-defer-orthy
#SBATCH -N 1
#SBATCH --ntasks-per-node=46
#SBATCH -p batch
#SBATCH --output=/home/workstation2/AppFiles/GraspKit-Workspace/data/rmcdhf_test_data/log/%j_%x.log
#SBATCH --error=/home/workstation2/AppFiles/GraspKit-Workspace/data/rmcdhf_test_data/log/%j_%x.log
export GRASP_REJECT_NODE_CHANGE=0
export GRASP_DEFER_ORTHY=1
export GRASP_RESULT_TAG=ni-defer-orthy-46mpi
exec zsh /home/workstation2/AppFiles/GraspKit-Workspace/rmcdhf_test/test/rmcdhf_orbopt/slurm/run_ni_as1_as2_chain_diagnostic.sbatch
