#!/bin/zsh
#SBATCH -J diagnose-rangular-nica
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH -p batch
#SBATCH --output=%j_%x.log
#SBATCH --error=%j_%x.log
. /usr/share/Modules/init/zsh
set -euo pipefail
module load mpi/openmpi-x86_64
module load grasp/grasp_2990_NNNP
root=/home/workstation2/AppFiles/GraspKit-Workspace
export GRASPKITTOOLS="$root/graspkit-tools"
export PATH="${GRASPKITTOOLS}/scripts:${PATH}"
unset VIRTUAL_ENV _OLD_VIRTUAL_PATH _OLD_VIRTUAL_PS1 _OLD_VIRTUAL_PYTHONHOME
source "${GRASPKITTOOLS}/.venv/bin/activate"
out="$root/data/rmcdhf_test_data/results/rangular-ni-ca-diagnostic-${SLURM_JOB_ID}"
mkdir -p "$out"
{
  echo "job=$SLURM_JOB_ID date=$(date -Is)"
  echo "rangular=$(command -v rangular_mpi)"
  sha256sum "$(command -v rangular_mpi)"
  echo '--- fixture comparison ---'
  sha256sum "$root/data/rmcdhf_test_data/inputs/Ni_Ca-like/e1_cv_NV/e1_cv_NVas1.c" "$root/data/rmcdhf_test_data/inputs/Ni_Ca-like/even1_cv/e1_cvas1.c"
} > "$out/environment.txt" 2>&1

for pair in nv optimized; do
  work="$out/$pair"; mkdir -p "$work"; cd "$work"
  if [[ $pair == nv ]]; then src="$root/data/rmcdhf_test_data/inputs/Ni_Ca-like/e1_cv_NV"; else src="$root/data/rmcdhf_test_data/inputs/Ni_Ca-like/even1_cv"; fi
  cp "$src/isodata" isodata
  if [[ $pair == nv ]]; then cp "$src/e1_cv_NVas1.c" rcsf.inp; else cp "$src/e1_cvas1.c" rcsf.inp; fi
  mkdir -p input_copies
  cp "$src"/*.c input_copies/
  mkdisks 1 /home/workstation2/caltmp/mpi_tmp > mkdisks.stdout 2>&1
  {
    echo "--- $pair ---"
    pwd
    ls -la
    echo '--- disks ---'; cat disks
    echo '--- rcsf files ---'; find . -maxdepth 1 -name 'rcsf*' -ls
    echo '--- checksums ---'; sha256sum rcsf.inp isodata
  } > inventory.txt 2>&1
  printf 'y\n' > rangular.stdin
  set +e
  mpirun -n 1 rangular_mpi < rangular.stdin > rangular.stdout 2>&1
  status=$?
  set -e
  echo "$status" > rangular.exitcode
  find . -maxdepth 1 -name 'rcsf*' -ls > rcsf.after.txt
done
diff -ruN "$out/nv" "$out/optimized" > "$out/nv_vs_optimized.diff" || true
printf 'status,complete\n' > "$out/status.csv"
