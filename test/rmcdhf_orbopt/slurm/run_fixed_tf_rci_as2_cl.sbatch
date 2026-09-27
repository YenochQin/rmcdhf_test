#!/bin/zsh
# Same-layer fixed-TF/RCI baseline for Cl I AS2 (debugging plan Section 5.1/5.4).
# The TF layer is regenerated from the accepted pair-strict AS1 anchor with the
# rcsf.inp, isodata and rwfnestimate dialogue of optimized r1 Job 663 and must be
# byte-identical to that run's starting estimate. The optimized r1 wave goes
# through the identical RCI, so both sides share CSF space, state set and
# Hamiltonian.
#SBATCH -J rmcdhf-fixed-tf-rci-as2-cl
#SBATCH -N 1
#SBATCH --ntasks-per-node=46
#SBATCH --cpus-per-task=1
#SBATCH -p batch
#SBATCH --output=/home/workstation2/AppFiles/GraspKit-Workspace/data/rmcdhf_test_data/log/%j_%x.log
#SBATCH --error=/home/workstation2/AppFiles/GraspKit-Workspace/data/rmcdhf_test_data/log/%j_%x.log

. /usr/share/Modules/init/zsh
set -euo pipefail
module load mpi/openmpi-x86_64
module load grasp/grasp_2990_NNNP

root=/home/workstation2/AppFiles/GraspKit-Workspace
export GRASPKITTOOLS=$root/graspkit-tools
export PATH=${GRASPKITTOOLS}/scripts:${PATH}
unset VIRTUAL_ENV _OLD_VIRTUAL_PATH _OLD_VIRTUAL_PS1 _OLD_VIRTUAL_PYTHONHOME
source ${GRASPKITTOOLS}/.venv/bin/activate
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1

data=$root/data/rmcdhf_test_data
optimized_run=$data/results/pair-physical-as2-cl-663
anchor=$data/results/pair-strict-as1-cl-r1-20260916013000/o1_vvas1.w
conf=o1_vvas2
se_max_n=3                  # largest spectroscopic n: 3s2 3p5
levels=(1 1)                # r1 rmcdhf state set

processor=${SLURM_NTASKS:-46}
out=$data/results/fixed-tf-rci-as2-cl-${SLURM_JOB_ID}
mpi_tmp=/home/workstation2/caltmp/fixed-tf-rci-as2-cl-${SLURM_JOB_ID}

mkdir -p "$out/tf" "$out/optimized"
cd "$out"
sha256sum "$anchor" "$optimized_run/rcsf.inp" "$optimized_run/isodata" \
    "$optimized_run/rwfn.inp" "$optimized_run/$conf.w" > inputs.sha256

cd "$out/tf"
cp "$anchor" previous.w
cp "$optimized_run/rcsf.inp" "$optimized_run/isodata" "$optimized_run/rwfnestimate.stdin" .
rwfnestimate < rwfnestimate.stdin > rwfnestimate.stdout 2>&1
if ! cmp -s rwfn.inp "$optimized_run/rwfn.inp"; then
    echo "ERROR: TF wave differs from the r1 starting estimate $optimized_run/rwfn.inp" >&2
    exit 1
fi
cp rwfn.inp "$conf.w"

cd "$out/optimized"
cp "$optimized_run/rcsf.inp" "$optimized_run/isodata" "$optimized_run/$conf.w" .

run_rci() {
    local side=$1
    cd "$out/$side"
    cp rcsf.inp "$conf.c"
    mkdisks "$processor" "$mpi_tmp/$side" > mkdisks.stdout 2>&1
    printf '%s\n' y "$conf" y n y n n y "$se_max_n" "${levels[@]}" > rci.stdin
    srun --mpi=pmix --cpu-bind=none --ntasks="$processor" rci_mpi \
        < rci.stdin > rci.stdout 2>&1
    test -s "$conf.cm"
    printf '%s\ny\ny\ny\n' "$conf" | jj2lsj > jj2lsj.stdout 2>&1
    rlevels "$conf.cm" > "$conf.level"
    python "$GRASPKITTOOLS/pyscript/read_level_to_csv.py" \
        -f "$conf.level" -lsj -o "${conf}_${side}_rci.csv"
    test -s "${conf}_${side}_rci.csv"
}
run_rci tf
run_rci optimized

echo 0 > "$out/fixed_tf_rci.exitcode"
echo "results: $out"
