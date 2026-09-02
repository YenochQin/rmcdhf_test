#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../../../../" && pwd)
results="$root/data/rmcdhf_test_data/results"
mkdir -p "$results"
full_job=$(sbatch --parsable --job-name=rmcdhf-full-20260831c \
  --output="$results/%j_rmcdhf-full.log" --error="$results/%j_rmcdhf-full.log" \
  --nodes=1 --ntasks=48 --partition=batch \
  --wrap="source /usr/share/Modules/init/bash; module load mpi/openmpi-x86_64; module load grasp/grasp_2990_NNNP; export GRASPKITTOOLS=$root/graspkit-tools; export PATH=\${GRASPKITTOOLS}/scripts:\${PATH}; unset VIRTUAL_ENV _OLD_VIRTUAL_PATH _OLD_VIRTUAL_PS1 _OLD_VIRTUAL_PYTHONHOME; source \${GRASPKITTOOLS}/.venv/bin/activate; cd $root/rmcdhf_test; export GRASP_BINDIR=/tmp/rmcdhf-build-debug/bin; export GRASP_SERIAL_BINDIR=/tmp/rmcdhf-build-debug/bin; bash test/rmcdhf_orbopt/run_matrix.sh rmcdhf-full-20260831c full")
manifest="$results/slurm_submission_manifest.txt"
{
  echo "submitted_at=$(date -Is)"
  echo "full_matrix_job=${full_job}"
  echo "full_output=$results/rmcdhf-full-20260831c"
} | tee "$manifest"
