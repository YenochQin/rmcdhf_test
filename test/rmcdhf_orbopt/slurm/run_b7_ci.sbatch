#!/bin/zsh
#SBATCH -J rmcdhf-b7-ci
#SBATCH -N 1
#SBATCH --ntasks-per-node=48
#SBATCH -p batch
#SBATCH --output=%j_%x.log
#SBATCH --error=%j_%x.log
. /usr/share/Modules/init/zsh
set -euo pipefail
module load mpi/openmpi-x86_64
module load grasp/grasp_2990_NNNP
export GRASPKITTOOLS="/home/workstation2/AppFiles/GraspKit-Workspace/graspkit-tools"
export PATH="${GRASPKITTOOLS}/scripts:${PATH}"
unset VIRTUAL_ENV _OLD_VIRTUAL_PATH _OLD_VIRTUAL_PS1 _OLD_VIRTUAL_PYTHONHOME
source "${GRASPKITTOOLS}/.venv/bin/activate"
root=/home/workstation2/AppFiles/GraspKit-Workspace
src=${root}/data/rmcdhf_test_data/results/recovered_20260831/tmp/rmcdhf-damping-20260825
out=${root}/data/rmcdhf_test_data/results/b7-rci-20260901
mkdir -p "$out"
run_one() {
  name=$1; source_dir=$2; work=$out/$name; mkdir -p "$work"; cd "$work"
  mkdisks "${SLURM_NTASKS:-48}" /home/workstation2/caltmp
  c=$(find "$source_dir" -maxdepth 1 -name '*.c' ! -name 'rcsf.inp' | head -1)
  w=$(find "$source_dir" -maxdepth 1 -name '*.w' ! -name 'previous.w' | head -1)
  test -n "$c" -a -n "$w"
  if [[ $name == ni_ca_like ]]; then iso="$root/data/rmcdhf_test_data/inputs/Ni_Ca-like/e1_cv_NV/isodata"; else iso="$root/data/rmcdhf_test_data/inputs/Ni_I/e1_vv2/isodata"; fi
  cp "$iso" isodata
  conf=b7
  cp "$c" b7.c
  cp "$w" b7.w
  mkdisks "${SLURM_NTASKS:-48}" /home/workstation2/caltmp/mpi_tmp > mkdisks.stdout 2>&1
  rci <<EOF > rci.stdout 2>&1
y
${conf}
y
n
y
n
n
y
3
1-2
1
1-3
1
1-2
EOF
  test -s b7.cm -a -s b7.csum
  printf '%s\n' b7 y y y | jj2lsj > jj2lsj.stdout 2>&1
  srun --mpi=pmix --cpu-bind=thread --ntasks="${SLURM_NTASKS:-48}" rhfs_mpi b7 --ci > rhfs.stdout 2>&1 || rhfs b7 --ci >> rhfs.stdout 2>&1
  rlevels b7.cm | tee b7.clevel
  python "${GRASPKITTOOLS}/pyscript/read_level_to_csv.py" -f b7.clevel -lsj -gj -o b7_rci.csv
  sha256sum b7.c b7.w b7.cm b7.csum b7.clevel b7_rci.csv > checksums.sha256
}
run_one ni_ca_like "$src/ni_ca_as2_damp_05"
run_one ni_i "$src/ni_i_as2_damp_05"
printf 'status,complete\n' > "$out/b7_status.csv"
