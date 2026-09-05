#!/usr/bin/env bash
set -euo pipefail

root=/home/workstation2/AppFiles/GraspKit-Workspace
log_dir=$root/data/rmcdhf_test_data/log
bindir=${GRASP_BINDIR:-$root/rmcdhf_test/build/bin}
mpi_tmp=${GRASP_MPI_TMP:-/home/workstation2/caltmp}
ranks=${GRASP_MPI_RANKS:-46}
mkdir -p "$log_dir"

common=(
  "--ntasks=$ranks"
  --cpus-per-task=1
  "--output=$log_dir/%j_%x.log"
  "--error=$log_dir/%j_%x.log"
  "--export=ALL,GRASP_BINDIR=$bindir,GRASP_MPI_TMP=$mpi_tmp"
)

submit() {
  local name=$1 tag=$2 script=$3 extra=${4:-}
  local export_args="GRASP_RESULT_TAG=$tag"
  [[ -n $extra ]] && export_args=",$export_args,$extra"
  sbatch "${common[@]}" \
    --job-name="$name" \
    --export="ALL,GRASP_BINDIR=$bindir,GRASP_MPI_TMP=$mpi_tmp,GRASP_MPI_RANKS=$ranks$export_args" \
    "$root/$script"
}

# Ni I: guard enabled baseline, then guard disabled, then deferred ORTHY.
submit ni581guard ni-guard-46mpi-$(date +%Y%m%d) \
  rmcdhf_test/test/rmcdhf_orbopt/slurm/run_ni_as1_as2_chain_diagnostic.sbatch \
  "GRASP_REJECT_NODE_CHANGE=1"
submit ni582open ni-open-46mpi-$(date +%Y%m%d) \
  rmcdhf_test/test/rmcdhf_orbopt/slurm/run_ni_as1_as2_chain_diagnostic.sbatch \
  "GRASP_REJECT_NODE_CHANGE=0"
submit ni-defer-orthy ni-defer-orthy-46mpi-$(date +%Y%m%d) \
  rmcdhf_test/test/rmcdhf_orbopt/slurm/run_ni_as1_as2_chain_diagnostic.sbatch \
  "GRASP_REJECT_NODE_CHANGE=0,GRASP_DEFER_ORTHY=1"

submit nica46 nica-46mpi-$(date +%Y%m%d) \
  rmcdhf_test/test/rmcdhf_orbopt/slurm/run_ni_ca_scaling_rank.sbatch
submit cl46 cl-chain-46mpi-$(date +%Y%m%d) \
  rmcdhf_test/test/rmcdhf_orbopt/slurm/run_cl_as_chain.sbatch
