#!/bin/zsh
# Strict fixed-orbital CI/RCI comparison for the completed Jobs 631/632.
#
# For each system this job creates an AS2 Thomas--Fermi wavefunction with
# rwfnestimate from the archived NV AS1 wavefunction, then runs exactly the
# same RCI calculation on that TF wavefunction and on the final all_new
# wavefunction from the orbital-isolation job.  The two systems are kept in a
# single serial job so that their inputs and post-processing cannot drift.
#
# No RMCDHF calculation is launched here.
#SBATCH -J rmcdhf-fixed-rci
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
out=$data_root/results/fixed-orbital-rci-pair-${SLURM_JOB_ID}
mkdir -p "$out"
mpi_tmp=/home/workstation2/caltmp/fixed-orbital-rci-${SLURM_JOB_ID}
mkdir -p "$mpi_tmp"
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1

test -x "$(command -v rangular_mpi)"
test -x "$(command -v rwfnestimate)"
test -x "$(command -v rci)"
test -x "$(command -v jj2lsj)"
test -x "$(command -v rlevels)"
test -s "$tools_root/pyscript/read_level_to_csv.py"

# The RCI state-selection dialogue is deliberately identical for the two
# systems.  It selects the same first three levels in each of the three J
# blocks used by the existing B7 reference jobs.
rci_stdin=$'y\nb7\ny\nn\ny\nn\nn\ny\n3\n1-2\n1\n1-3\n1\n1-2\n'

run_rangular() {
  local work=$1
  cd "$work"
  mkdisks 1 "$mpi_tmp" > mkdisks.stdout 2>&1
  local disk_root
  disk_root=$(head -n 1 disks)
  local expected_disk="'$work'"
  [[ $disk_root == "$expected_disk" ]] || {
    echo "invalid disks directory in $work: $disk_root" >&2
    return 2
  }
  printf 'y\n' > rangular.stdin
  if [[ -n ${SLURM_JOB_ID:-} ]]; then
    srun --mpi=pmix --cpu-bind=thread --ntasks=1 \
      rangular_mpi < rangular.stdin > rangular.stdout 2>&1
  else
    mpirun -n 1 rangular_mpi < rangular.stdin > rangular.stdout 2>&1
  fi
}

make_tf_wave() {
  local work=$1
  local csf=$2
  local previous=$3
  local isodata=$4
  mkdir -p "$work"
  cd "$work"
  cp "$isodata" isodata
  cp "$csf" rcsf.inp
  cp "$previous" previous.w
  run_rangular "$work"
  printf 'y\n1\nprevious.w\n*\n2\n*\n4\n*\n4\n' \
    > rwfnestimate.stdin
  rwfnestimate < rwfnestimate.stdin > rwfnestimate.stdout 2>&1
  test -s rwfn.inp
  sha256sum isodata rcsf.inp previous.w rwfn.inp > checksums.sha256
}

run_fixed_rci() {
  local case_slug=$1
  local case_label=$2
  local csf=$3
  local isodata=$4
  local tf_previous=$5
  local optimized=$6
  local case_out=$out/$case_slug
  local tf_out=$case_out/tf
  local optimized_out=$case_out/optimized
  mkdir -p "$case_out"

  make_tf_wave "$tf_out" "$csf" "$tf_previous" "$isodata"
  test -s "$optimized"

  printf 'case,%s\nlabel,%s\ncsf,%s\n' \
    "$case_slug" "$case_label" "$csf" > "$case_out/manifest.csv"
  printf 'source,kind,path\n' > "$case_out/wave_sources.csv"
  printf 'tf,TF,%s/rwfn.inp\noptimized,optimized,%s\n' \
    "$tf_out" "$optimized" >> "$case_out/wave_sources.csv"
  sha256sum "$csf" "$tf_out/rwfn.inp" "$optimized" \
    >> "$case_out/manifest.csv"

  local kind
  for kind in tf optimized; do
    local wave
    local work=$case_out/$kind/rci
    if [[ $kind == tf ]]; then
      wave=$tf_out/rwfn.inp
    else
      wave=$optimized
    fi
    mkdir -p "$work"
    cd "$work"
    cp "$isodata" isodata
    cp "$csf" b7.c
    cp "$wave" b7.w
    printf '%s\n' "$rci_stdin" > rci.stdin
    mkdisks 1 "$mpi_tmp" > mkdisks.stdout 2>&1
    rci < rci.stdin > rci.stdout 2>&1
    test -s b7.cm
    test -s b7.csum
    printf '%s\n' b7 y y y | jj2lsj > jj2lsj.stdout 2>&1
    rlevels b7.cm | tee b7.level
    python "$tools_root/pyscript/read_level_to_csv.py" \
      -f b7.level -lsj -o b7_rci.csv
    sha256sum b7.c b7.w b7.cm b7.csum b7.level b7_rci.csv \
      > checksums.sha256
    printf 'status,complete\ncase,%s\nkind,%s\n' \
      "$case_slug" "$kind" > status.csv
  done
}

run_fixed_rci \
  nii \
  'Ni I' \
  "$data_root/inputs/Ni_I/e1_vv2_NV/e1_vv2_NVas2.c" \
  "$data_root/inputs/Ni_I/e1_vv2_NV/isodata" \
  "$data_root/inputs/Ni_I/e1_vv2_NV/e1_vv2_NVas1.w" \
  "$data_root/results/orbital-iso-nii-631/as2-all_new/e1_vv2as2.w"

run_fixed_rci \
  nica \
  'Ni/Ca-like' \
  "$data_root/inputs/Ni_Ca-like/e1_cv_NV/e1_cv_NVas2.c" \
  "$data_root/inputs/Ni_Ca-like/e1_cv_NV/isodata" \
  "$data_root/inputs/Ni_Ca-like/e1_cv_NV/e1_cv_NVas1.w" \
  "$data_root/results/orbital-iso-nica-632/as2-all_new/e1_cvas2.w"

sha256sum "$out"/nii/{tf,optimized}/rci/b7.* \
  "$out"/nica/{tf,optimized}/rci/b7.* > "$out/all_outputs.sha256"
printf 'status,complete\njob_id,%s\n' "$SLURM_JOB_ID" > "$out/status.csv"
echo "results: $out"
