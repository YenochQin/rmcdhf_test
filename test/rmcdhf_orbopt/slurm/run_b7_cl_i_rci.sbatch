#!/bin/zsh
# Fixed-orbital RCI attribution test for the final Cl I AS5 wavefunction.
#SBATCH -J rmcdhf-b7-cl
#SBATCH -N 1
#SBATCH --ntasks-per-node=1
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
source_dir=$root/data/rmcdhf_test_data/results/cl-as-chain-580/cl_as5_balanced_damped
out=$root/data/rmcdhf_test_data/results/b7-rci-cl-${SLURM_JOB_ID}
mkdir -p $out
cd $out
test -s $source_dir/o1_vvas5.c
test -s $source_dir/o1_vvas5.w
cp $root/data/rmcdhf_test_data/inputs/Cl_I/o1_vv1/isodata isodata
cp $source_dir/o1_vvas5.c b7.c
cp $source_dir/o1_vvas5.w b7.w
mkdisks 1 /home/workstation2/caltmp > mkdisks.stdout 2>&1
printf 'y\nb7\ny\nn\ny\nn\nn\ny\n3\n1\n1\n' | rci > rci.stdout 2>&1
test -s b7.cm
test -s b7.csum
printf '%s\n' b7 y y y | jj2lsj > jj2lsj.stdout 2>&1
rlevels b7.cm | tee b7.level
python ${GRASPKITTOOLS}/pyscript/read_level_to_csv.py -f b7.level -lsj -o b7_rci.csv
sha256sum b7.c b7.w b7.cm b7.csum b7.level b7_rci.csv > checksums.sha256
printf 'status,complete\n' > status.csv
