#!/bin/zsh
# Targeted diagnostic: isolate the first newly added orbital that changes the
# spectrum.  Run once with DIAG_CASE=ni_i and once with DIAG_CASE=ni_ca_like.
# AS1 is taken from the archived external AS1 wavefunction; only AS2 variants
# are run, so this does not repeat the completed AS1 production jobs.
#SBATCH -J rmcdhf-orbital-isolation
#SBATCH -N 1
#SBATCH --ntasks-per-node=46
#SBATCH --cpus-per-task=1
#SBATCH -p batch
#SBATCH --time=08:00:00
#SBATCH --output=/home/workstation2/AppFiles/GraspKit-Workspace/data/rmcdhf_test_data/log/%j_%x.log
#SBATCH --error=/home/workstation2/AppFiles/GraspKit-Workspace/data/rmcdhf_test_data/log/%j_%x.log

. /usr/share/Modules/init/zsh
set -euo pipefail
module load mpi/openmpi-x86_64
module load grasp/grasp_2990_NNNP

root=/home/workstation2/AppFiles/GraspKit-Workspace
external=/home/workstation2/nvmesdd2T/rmcdhf_test_cal
export GRASPKITTOOLS=$root/graspkit-tools
export GRASP_TEST_DATA_ROOT=$external
export PATH=${GRASPKITTOOLS}/scripts:${PATH}
unset VIRTUAL_ENV _OLD_VIRTUAL_PATH _OLD_VIRTUAL_PS1 _OLD_VIRTUAL_PYTHONHOME
source ${GRASPKITTOOLS}/.venv/bin/activate
cd $root/rmcdhf_test
unset GRASP_VARIED_OVERRIDE GRASP_PREVIOUS_WAVE GRASP_ISODATA_SOURCE

case_name=${DIAG_CASE:-ni_i}
case "$case_name" in
  ni_i)
    case_slug=nii
    source_dir=$external/Ni_I/e1_vv2
    prefix=e1_vv2
    previous=$source_dir/e1_vv2as1.w
    isodata=$external/Ni_I/e1_vv2_NV/isodata
    old_varied='5s,4p,4d'
    new_orbitals=(6s 5p 5d 4f)
    ;;
  ni_ca_like)
    # rangular_mpi stores the absolute rcsf.inp path in CHARACTER*128;
    # keep this output path short enough for that legacy limit.
    case_slug=nica
    source_dir=$external/Ni_Ca-like/e1_cv
    prefix=e1_cv
    previous=$source_dir/e1_cvas1.w
    isodata=$source_dir/isodata
    old_varied='4s,4p,4d,4f'
    new_orbitals=(5s 5p 5d 5f 5g)
    ;;
  *)
    echo "DIAG_CASE must be ni_i or ni_ca_like" >&2
    exit 2
    ;;
esac

test -s "$previous"
export GRASP_BINDIR=$root/rmcdhf_test/build-gatherv/bin
export GRASP_MPI_TMP=/home/workstation2/caltmp/orbital-isolation-${SLURM_JOB_ID}
export GRASP_OMP_THREADS=1 OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
ranks=${SLURM_NTASKS:-46}
[[ $ranks == 46 ]] || { echo "ranks ($ranks) != allocated CPUs (46)" >&2; exit 2; }
test -x "$GRASP_BINDIR/rmcdhf_mpi"

out=$root/data/rmcdhf_test_data/results/orbital-iso-${case_slug}-${SLURM_JOB_ID}
mkdir -p "$out"
printf 'case,%s\nprevious_wave,%s\nbinary,%s\n' \
  "$case_name" "$previous" "$GRASP_BINDIR/rmcdhf_mpi" > "$out/manifest.csv"
sha256sum "$GRASP_BINDIR/rmcdhf_mpi" >> "$out/manifest.csv"

common=(GRASP_ALLOW_UNBALANCED=1 \
  GRASP_TRACE_ORBOPT=1 GRASP_TRACE_INITIAL_ORBITALS=1 \
  GRASP_TRACE_RWFN=1 GRASP_DEBUG_EIGENVECTORS=1 \
  GRASP_ALLOW_RADIAL_GRID_DIFFERENCE=1 GRASP_ALLOW_ENERGY_DIFFERENCES=1 \
  GRASP_RMCDHF_TIMEOUT=45m GRASP_ABORT_ON_ORBOPT_ERROR=1 \
  GRASP_EXPECT_RMCDHF_FAILURE=1)

run_variant() {
  local variant=$1
  local varied=$2
  local variant_dir=$out/as2-$variant
  local -a variant_env
  variant_env=(GRASP_PREVIOUS_WAVE="$previous" GRASP_ISODATA_SOURCE="$isodata")
  if [[ $varied != __default__ ]]; then
    variant_env+=(GRASP_VARIED_OVERRIDE="$varied")
  fi
  set +e
  env "${common[@]}" "${variant_env[@]}" \
    bash test/rmcdhf_orbopt/run_data_case.sh \
    "$case_name" optimized "$variant_dir" "$ranks" estimate 2
  local runner_status=$?
  set -e
  local rm_status=missing
  if [[ -f $variant_dir/rmcdhf.exitcode ]]; then
    rm_status=$(cat "$variant_dir/rmcdhf.exitcode")
  fi
  # Quote the varied list because it is a comma-separated orbital list.
  printf '%s,"%s",%s,%s\n' "$variant" "$varied" "$runner_status" "$rm_status" \
    >> "$out/variant_status.csv"
}

printf 'variant,varied,runner_exit,rmcdhf_exit\n' > "$out/variant_status.csv"
run_variant freeze_new "$old_varied"
run_variant all_new __default__
for orbital in "${new_orbitals[@]}"; do
  run_variant "only-$orbital" "$orbital"
done

python3 "$root/rmcdhf_test/test/rmcdhf_orbopt/summarize_orbital_isolation.py" \
  "$out" "$case_name" > "$out/diagnostic_summary.csv"
printf 'status,complete\n' > "$out/status.csv"
