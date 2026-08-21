# RMCDHF Orbital-Optimization Data Tests

`run_data_case.sh` reproduces the Ni I and Ni/Ca-like workflows archived in
`test/data/` without modifying those inputs. It uses the repository's current
`rangular_mpi`, `rwfnestimate`, and `rmcdhf_mpi`, loads
`mpi/openmpi-x86_64`, enables orbital tracing, and writes every artifact to a
new output directory.

The runner sets `OMP_NUM_THREADS=1` and `OPENBLAS_NUM_THREADS=1`, because the
FlexiBLAS-managed OpenBLAS backend is OpenMP-enabled. Override both with
`GRASP_OMP_THREADS` only when deliberately testing hybrid MPI/OpenMP runs.

```sh
bash test/rmcdhf_orbopt/run_data_case.sh \
  ni_i optimized /tmp/ni-i-as2 4 estimate 2
bash test/rmcdhf_orbopt/run_data_case.sh \
  ni_ca_like nv /tmp/ni-ca-nv-as1 4 estimate 1
```

Arguments select the data family, `optimized`, `nv`, `minus_only`, or
`balanced`, output directory, MPI
rank count, initial-wave mode, and AS stage (1 or 2). `estimate` follows the
original script by initializing from the preceding stage. `archived` restarts
from the archived wavefunction and is useful for convergence-repeatability
checks. The runner deliberately uses the archived stage `.c` file instead of
`*raw.c`, so current tests isolate RMCDHF behavior from zero-first CSF
generation differences.

`minus_only` implements diagnostic variant B2 by optimizing the minus member
of each relativistic pair. `balanced` implements B3 by optimizing both members
and enables `GRASP_REQUIRE_BALANCED_PAIR=1`. These experimental variants report
their expected energy differences from the original optimized archive without
failing the run.

Inspect these outputs:

- `archive_comparison.csv`: CSF count, radial-grid size, and all selected
  eigenenergy differences versus the archived `.sum`.
- `orbopt_summary.csv`: per-iteration energy spacing, minimum orbital overlap,
  largest symmetric radius-change factor, node changes, solver fallbacks, and
  the corresponding metrics for the actually accepted (possibly damped)
  orbital.
- `orbopt_trace.csv` and `rmcdhf.stdout`: complete diagnostic evidence and
  relativistic-pair warnings.

Compare the lowest positive-parity J=2,3,4 levels across variants with:

```sh
python3 test/rmcdhf_orbopt/compare_fine_structure.py \
  NV=/tmp/ni-nv/rmcdhf.sum B1=/tmp/ni-b1/rmcdhf.sum \
  B2=/tmp/ni-b2/rmcdhf.sum B3=/tmp/ni-b3/rmcdhf.sum
```

The current AS2 B2/B3 findings are recorded in `RESULTS.md`.

Optional B4/guard controls are passed through the environment, for example:

```sh
GRASP_ORBITAL_DAMPING=-0.5 \
  bash test/rmcdhf_orbopt/run_data_case.sh \
  ni_i balanced /tmp/ni-b4 24 estimate 2

GRASP_ORBITAL_DAMPING=-0.5 GRASP_ORBITAL_GUARD=1 \
GRASP_EXPECT_RMCDHF_FAILURE=1 \
  bash test/rmcdhf_orbopt/run_data_case.sh \
  ni_i balanced /tmp/ni-guard 24 estimate 2
```

Guard thresholds are configured with `GRASP_MIN_ORBITAL_OVERLAP`,
`GRASP_MAX_RADIUS_RATIO`, `GRASP_REJECT_NODE_CHANGE`, and
`GRASP_MAX_REJECTS_PER_ORBITAL`. Expected-failure mode preserves the trace and
records the real MPI exit status in `rmcdhf.exitcode`.

An existing output directory is rejected to prevent accidental data loss.
