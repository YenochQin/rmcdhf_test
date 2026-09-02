#!/bin/zsh
#SBATCH -J diagnose-mkdisks
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
out="$root/data/rmcdhf_test_data/results/mkdisks-diagnostic-${SLURM_JOB_ID}"
mkdir -p "$out"
cd "$out"
{
  echo "pwd=$(pwd)"
  echo "PATH=$PATH"
  type -a mkdisks
  command -v mkdisks
  realpath "$(command -v mkdisks)"
  sha256sum "$(command -v mkdisks)"
  echo '--- mkdisks source ---'
  sed -n '1,220p' "$(command -v mkdisks)"
  echo '--- invocation ---'
  mkdisks "${SLURM_NTASKS:-1}" /home/workstation2/caltmp/mpi_tmp
  echo '--- disks ---'
  cat disks
  echo '--- paths ---'
  while IFS= read -r line; do p=${line#\'}; p=${p%\'}; ls -ld "$p" || true; done < disks
} > diagnostic.txt 2>&1
