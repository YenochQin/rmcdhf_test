#!/usr/bin/env bash
# Run three fixed-damping matrices under identical CPU affinity and compare.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <output-root>" >&2
    exit 2
fi

output_root=$1
if [[ -e $output_root ]]; then
    echo "output root already exists: $output_root" >&2
    exit 2
fi

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
matrix=$repo_root/test/rmcdhf_orbopt/run_matrix.sh
checker=$repo_root/test/rmcdhf_orbopt/check_damping_repeatability.py
mkdir -p "$output_root"
output_root=$(cd "$output_root" && pwd)

export GRASP_DAMPING_RANKS=${GRASP_DAMPING_RANKS:-4}
export GRASP_DAMPING_THREADS=${GRASP_DAMPING_THREADS:-12}

for repeat in 1 2 3; do
    bash "$matrix" "$output_root/repeat${repeat}" damping
done

python3 "$checker" --reference "$output_root/repeat1" \
    R2="$output_root/repeat2" R3="$output_root/repeat3" \
    > "$output_root/damping_repeatability.csv"
printf 'repeats,3\nstatus,complete\n' > "$output_root/repeatability_status.csv"
echo "damping repeatability matrix complete: $output_root"
