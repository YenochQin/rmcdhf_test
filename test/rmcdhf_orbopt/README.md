# RMCDHF Orbital-Optimization Data Tests

`run_data_case.sh` reproduces the Ni I and Ni/Ca-like workflows archived in
`test/data/` without modifying those inputs. It loads the site GRASP module
(`grasp/grasp_2990_NNNP`) for the external `rangular_mpi` and `rwfnestimate`
programs, while `rmcdhf_mpi` is always taken from this repository's build.
The MPI module and orbital tracing are enabled automatically, and every
artifact is written to a new output directory.

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

After a successful RMCDHF run, the runner also performs the standard GRASP
post-processing sequence: `rsave`, `jj2lsj`, MPI `rhfs_mpi`, and `rlevels`.
Because `rsave` renames the generic `rmcdhf.sum`, the runner restores a copy
under that generic name for the comparison scripts and matrix-level reports.
The resulting `.level` file is converted with
`graspkit-tools/pyscript/read_level_to_csv.py` (including LSJ and g_J data) to
`${prefix}as${stage}_rmcdhf.csv`. Set `GRASPKITTOOLS` when the sibling
`graspkit-tools` checkout is elsewhere.
If the selected GRASP module does not ship `rhfs_mpi` (the current
`grasp/grasp_2990_NNNP` module ships only `rhfs`), the runner reports a warning
and uses serial `rhfs` for this post-processing-only step.

Set `GRASP_MODULE` to use a site-specific GRASP module name.  The local
RMCDHF executable directory can be overridden with
`GRASP_RMCDHF_MPI_BINDIR` (or the legacy `GRASP_BINDIR` fallback); the latter
no longer needs to contain `rangular_mpi` or `rwfnestimate`.

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

Strict convergence is enabled without changing stdin:

```sh
GRASP_STRICT_SCF=1 bash test/rmcdhf_orbopt/run_data_case.sh \
  ni_ca_like balanced /tmp/ni-ca-strict 1 estimate 1
```

`convergence_check.txt` verifies that legacy runs stop on the historical
orbital-or-energy condition.  In strict mode it verifies that the first
iteration has no valid previous-energy comparison and that both criteria pass
for two consecutive iterations before the program exits.

Run the available automated matrix with:

```sh
GRASP_BINDIR=/path/to/current/bin \
  bash test/rmcdhf_orbopt/run_matrix.sh /tmp/rmcdhf-matrix smoke
```

The `smoke` profile covers B0--B6 and strict convergence on Ni/Ca-like AS1.
B5 sets `GRASP_DEFER_ORTHY=1` to orthogonalize only at the macro-iteration
boundary.  On the current Ni/Ca-like fixture this produces a non-finite
weighted energy, so the smoke matrix records B5 as an expected failure; SCF
now stops immediately on non-finite weighted energy instead of exhausting its
iteration limit.  B6 sets `GRASP_STRICT_METHOD3=1`, which fixes all varied orbitals to
METHOD=3 and terminates instead of falling back to METHOD=2.  The `cl` profile
runs the corresponding Cl I AS1 B0--B6 matrix, writes a
half-integer-J fine-structure comparison, and independently cross-checks B4
iteration wavefunctions.  `full` adds both Ni data families, AS1/AS2 and MPI
1/2/4 balanced AS2 runs; it also chains the damped balanced Cl I wavefunctions
through AS2--AS5 using `GRASP_PREVIOUS_WAVE`, instead of restarting each stage
from the archived unbalanced wavefunction.  The Cl matrix also reruns B3 with
serial `rangular`/`rmcdhf`; the full profile adds MPI 2/4-rank B4 comparisons.
It also runs a B8 equal-weight comparison through `GRASP_LEVEL_WEIGHT=1`;
supported automatic values are 1 (equal) and 5 (statistical).

The `damping` profile completes the B4 parameter comparison at
`ODAMP=-0.2,-0.5,-0.8` for Cl I AS1, Ni/Ca-like AS2, and Ni I AS2.  It writes
one summary CSV per data family with raw and accepted orbital metrics, node
changes, solver fallbacks, and final fine-structure intervals.  One MPI rank
and one BLAS thread are used by default; controlled performance runs can set
`GRASP_DAMPING_RANKS` and `GRASP_DAMPING_THREADS`:

```sh
GRASP_DAMPING_RANKS=4 GRASP_DAMPING_THREADS=12 \
  bash test/rmcdhf_orbopt/run_matrix.sh /tmp/rmcdhf-damping damping
```

When more than one thread is requested, the runner maps each MPI rank to
`PE=GRASP_OMP_THREADS` distinct cores and enables core-level OpenMP binding.
Without this explicit OpenMPI mapping, the default `bind-to core` policy would
confine all threads in a rank to one core.  The exact launcher and thread
settings are saved in `mpi_launcher.txt`.

Run three complete matrices and compare runs 2 and 3 with run 1 to give every
damping variant three executions under the same 4-rank, 12-core-per-rank
configuration:

```sh
GRASP_BINDIR=/path/to/current/bin \
  bash test/rmcdhf_orbopt/run_damping_repeats.sh /tmp/rmcdhf-damping-repeats
```

The repeatability checker requires identical iteration counts, node-change
counts, fallback counts, and ordering. Floating-point summary fields must
agree within `1e-6` by default.

For independent wavefunction checks, set `GRASP_TRACE_RWFN=1`.  The program
then saves `rwfn.out.iterNNN` after each macro iteration.  The runner writes
`rwfn_metrics.csv` by parsing those unformatted G92RWF files independently of
the in-process trace, and `rwfn_crosscheck.csv` verifies that overlap and
radius-factor trends correlate with the internal accepted metrics:

```sh
GRASP_TRACE_RWFN=1 bash test/rmcdhf_orbopt/run_data_case.sh \
  ni_ca_like balanced /tmp/ni-ca-rwfn 1 estimate 1
```

This diagnostic is default-off because iteration snapshots add disk I/O.  The
external calculation uses the recorded radial grid and trapezoidal integration
instead of GRASP's internal `QUAD`, making it useful as an independent trend
check rather than a bitwise duplicate of the internal metric.

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
