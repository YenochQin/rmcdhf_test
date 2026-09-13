#!/bin/zsh
# Matched-AS1 TF control for the completed Jobs 631/632.
#
# The previous fixed-orbital pair used the archived _NV AS1 wavefunctions for
# its TF side.  This control preserves each isolation job's actual AS1
# previous.w, estimates only the AS2 orbitals, and runs the same fixed RCI.
# The optimized RCI CSVs are already available from Job 635 and are not rerun.
#SBATCH -J rmcdhf-matched-tf
#SBATCH -N 1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH -p batch
#SBATCH --time=02:00:00
#SBATCH --output=/home/workstation2/AppFiles/GraspKit-Workspace/data/rmcdhf_test_data/log/%j_%x.log
#SBATCH --error=/home/workstation2/AppFiles/GraspKit-Workspace/data/rmcdhf_test_data/log/%j_%x.log

. /usr/share/Modules/init/zsh
set -euo pipefail
module load mpi/openmpi-x86_64
module load grasp/grasp_2990_NNNP

root=/home/workstation2/AppFiles/GraspKit-Workspace
tools_root=$root/graspkit-tools
export GRASPKITTOOLS=$tools_root
export PATH=$tools_root/scripts:$PATH
unset VIRTUAL_ENV _OLD_VIRTUAL_PATH _OLD_VIRTUAL_PS1 _OLD_VIRTUAL_PYTHONHOME
source "$tools_root/.venv/bin/activate"

data_root=$root/data/rmcdhf_test_data
out=$data_root/results/matched-tf-rci-${SLURM_JOB_ID}
mkdir -p "$out"
mpi_tmp=/home/workstation2/caltmp/matched-tf-rci-${SLURM_JOB_ID}
mkdir -p "$mpi_tmp"
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1

for executable in rangular_mpi rwfnestimate rci jj2lsj rlevels; do
  test -x "$(command -v "$executable")"
done
test -s "$tools_root/pyscript/read_level_to_csv.py"

rci_stdin=$'y\nb7\ny\nn\ny\nn\nn\ny\n3\n1-2\n1\n1-3\n1\n1-2\n'

make_tf() {
  local work=$1 csf=$2 previous=$3 isodata=$4
  mkdir -p "$work"
  cd "$work"
  cp "$csf" rcsf.inp
  cp "$previous" previous.w
  cp "$isodata" isodata
  mkdisks 1 "$mpi_tmp" > mkdisks.stdout 2>&1
  [[ $(head -n 1 disks) == "'$work'" ]]
  printf 'y\n' > rangular.stdin
  srun --mpi=pmix --cpu-bind=thread --ntasks=1 \
    rangular_mpi < rangular.stdin > rangular.stdout 2>&1
  printf 'y\n1\nprevious.w\n*\n2\n*\n4\n*\n4\n' > rwfnestimate.stdin
  rwfnestimate < rwfnestimate.stdin > rwfnestimate.stdout 2>&1
  test -s rwfn.inp
  sha256sum rcsf.inp previous.w rwfn.inp > checksums.sha256
}

run_tf_rci() {
  local slug=$1 label=$2 csf=$3 isodata=$4 previous=$5 optimized_rci=$6
  local case_out=$out/$slug
  local tf=$case_out/tf
  local work=$case_out/rci
  mkdir -p "$case_out"
  make_tf "$tf" "$csf" "$previous" "$isodata"
  mkdir -p "$work"
  cd "$work"
  cp "$isodata" isodata
  cp "$csf" b7.c
  cp "$tf/rwfn.inp" b7.w
  printf '%s' "$rci_stdin" > rci.stdin
  mkdisks 1 "$mpi_tmp" > mkdisks.stdout 2>&1
  [[ $(head -n 1 disks) == "'$work'" ]]
  rci < rci.stdin > rci.stdout 2>&1
  test -s b7.cm
  test -s b7.csum
  printf '%s\n' b7 y y y | jj2lsj > jj2lsj.stdout 2>&1
  rlevels b7.cm | tee b7.level
  python "$tools_root/pyscript/read_level_to_csv.py" \
    -f b7.level -lsj -o b7_rci.csv
  sha256sum b7.c b7.w b7.cm b7.csum b7.level b7_rci.csv > checksums.sha256
  printf 'case,%s\nlabel,%s\nmatched_previous,%s\noptimized_rci,%s\n' \
    "$slug" "$label" "$previous" "$optimized_rci" > "$case_out/manifest.csv"
  printf 'status,complete\ncase,%s\n' "$slug" > status.csv
}

run_tf_rci \
  nii 'Ni I' \
  "$data_root/inputs/Ni_I/e1_vv2_NV/e1_vv2_NVas2.c" \
  "$data_root/inputs/Ni_I/e1_vv2_NV/isodata" \
  "$data_root/results/orbital-iso-nii-631/as2-all_new/previous.w" \
  "$data_root/results/fixed-orbital-rci-pair-635/nii/optimized/rci/b7_rci.csv"

run_tf_rci \
  nica 'Ni/Ca-like' \
  "$data_root/inputs/Ni_Ca-like/e1_cv_NV/e1_cv_NVas2.c" \
  "$data_root/inputs/Ni_Ca-like/e1_cv_NV/isodata" \
  "$data_root/results/orbital-iso-nica-632/as2-all_new/previous.w" \
  "$data_root/results/fixed-orbital-rci-pair-635/nica/optimized/rci/b7_rci.csv"

printf 'status,complete\njob_id,%s\n' "$SLURM_JOB_ID" > "$out/status.csv"
sha256sum "$out"/nii/rci/b7.* "$out"/nica/rci/b7.* > "$out/all_outputs.sha256"
echo "results: $out"
