# RMCDHF Orbital-Optimization Data Tests

## Slurm `mkdisks` 路径注意事项

Job 511 的诊断确认，当前 `mkdisks` 的第二个参数是基础目录，脚本会
自动追加 `/mpi_tmp`。在统一接口前，不要把已经以 `/mpi_tmp` 结尾的路径
直接传给该版本脚本，否则会生成 `/mpi_tmp/mpi_tmp` 并导致
`rangular_mpi` 找不到 `rcsf` 工作目录。诊断证据见
`data/rmcdhf_test_data/results/mkdisks-diagnostic-511/diagnostic.txt`。

`run_data_case.sh` reproduces the Ni I and Ni/Ca-like workflows archived in
`../data/rmcdhf_test_data/inputs/` without modifying those inputs. All new
results are stored below `../data/rmcdhf_test_data/results/`; paths outside
that directory are rejected. The runner loads the site GRASP module
(`grasp/grasp_2990_NNNP`) for the external `rangular_mpi` and `rwfnestimate`
programs, while `rmcdhf_mpi` is always taken from this repository's build.
The MPI module and orbital tracing are enabled automatically, and every
artifact is written to a new output directory.

The runner sets `OMP_NUM_THREADS=1` and `OPENBLAS_NUM_THREADS=1`, because the
FlexiBLAS-managed OpenBLAS backend is OpenMP-enabled. Override both with
`GRASP_OMP_THREADS` only when deliberately testing hybrid MPI/OpenMP runs.

On the 48-core reference node, production-scale RMCDHF jobs must use 48 MPI
ranks with `GRASP_OMP_THREADS=1`. The RMCDHF workload is primarily distributed
by MPI; `4 ranks × 12 BLAS threads` was observed to use only about 8% total CPU
in some phases. Runs with 1, 2, or 4 ranks are process-count repeatability
diagnostics, not production performance configurations.

```sh
bash test/rmcdhf_orbopt/run_data_case.sh \
  ni_i optimized ni-i-as2 4 estimate 2
bash test/rmcdhf_orbopt/run_data_case.sh \
  ni_ca_like nv ni-ca-nv-as1 4 estimate 1
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
  NV=../data/rmcdhf_test_data/results/ni-nv/rmcdhf.sum \
  B1=../data/rmcdhf_test_data/results/ni-b1/rmcdhf.sum \
  B2=../data/rmcdhf_test_data/results/ni-b2/rmcdhf.sum \
  B3=../data/rmcdhf_test_data/results/ni-b3/rmcdhf.sum
```

The current AS2 B2/B3 findings are recorded in `RESULTS.md`.

Strict convergence is enabled without changing stdin:

```sh
GRASP_STRICT_SCF=1 bash test/rmcdhf_orbopt/run_data_case.sh \
  ni_ca_like balanced ni-ca-strict 1 estimate 1
```

`convergence_check.txt` verifies that legacy runs stop on the historical
orbital-or-energy condition.  In strict mode it verifies that the first
iteration has no valid previous-energy comparison and that both criteria pass
for two consecutive iterations before the program exits.

Run the available automated matrix with:

```sh
GRASP_BINDIR=/path/to/current/bin \
  bash test/rmcdhf_orbopt/run_matrix.sh rmcdhf-matrix smoke
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

For independent wavefunction checks, set `GRASP_TRACE_RWFN=1`.  The program
then saves `rwfn.out.iterNNN` after each macro iteration.  The runner writes
`rwfn_metrics.csv` by parsing those unformatted G92RWF files independently of
the in-process trace, and `rwfn_crosscheck.csv` verifies that overlap and
radius-factor trends correlate with the internal accepted metrics:

```sh
GRASP_TRACE_RWFN=1 bash test/rmcdhf_orbopt/run_data_case.sh \
  ni_ca_like balanced ni-ca-rwfn 1 estimate 1
```

This diagnostic is default-off because iteration snapshots add disk I/O.  The
external calculation uses the recorded radial grid and trapezoidal integration
instead of GRASP's internal `QUAD`, making it useful as an independent trend
check rather than a bitwise duplicate of the internal metric.

Optional B4/guard controls are passed through the environment, for example:

```sh
GRASP_ORBITAL_DAMPING=-0.5 \
  bash test/rmcdhf_orbopt/run_data_case.sh \
  ni_i balanced ni-b4 24 estimate 2

GRASP_ORBITAL_DAMPING=-0.5 GRASP_ORBITAL_GUARD=1 \
GRASP_EXPECT_RMCDHF_FAILURE=1 \
  bash test/rmcdhf_orbopt/run_data_case.sh \
  ni_i balanced ni-guard 24 estimate 2
```

The SCF-round guard can scope its CI identity and energy-order checks to the
physical roots that must retain their meaning.  `GRASP_ROUND_TARGET_STATES`
is a comma/space/semicolon/colon-separated list of **1-based global state
indices** in the `NEWCOmpi` order.  The minimal 46-rank probe supplies
`4,7,8` for the Ni fixtures (the J=2, J=3, and J=4 roots of the target
`^3F_J` sequence) and `1,2` for Cl I; set the per-case variables
`GRASP_ROUND_TARGET_STATES_NI_I`, `GRASP_ROUND_TARGET_STATES_NICA`, or
`GRASP_ROUND_TARGET_STATES_CL_I` when the ASF selection changes.  With a
target list, low CI overlap in untracked auxiliary roots remains diagnostic
but does not reject an otherwise stable target set.  The complete assignment
is retained in memory; `round_nonidentity` reports any permutation and
`round_target` records each target's mapping.
The reported value is the absolute dot product of CI coefficient vectors in
the unchanged CSF ordering. Because the radial orbitals change between rounds,
it is a root-continuity proxy, not a biorthogonal many-electron ASF overlap.
Use final LSJ/dominant-configuration checks and a fixed-reference comparison
to detect accumulated term drift.

Run the offline assignment/target-order checks without submitting a job:

```sh
python3 test/rmcdhf_orbopt/test_round_state_logic.py
```

The target overlap gate follows the old-root column of the per-block
Hungarian assignment.  This matters when a candidate exchanges row positions
with another CI root: target states are specified by their previous global
state indices, so measuring the candidate row would test the wrong root.  When
round tracing is enabled, each guarded iteration also emits `round_target`
rows.  In those rows `index` is the old target state, `index2` is its mapped
candidate row, `position` is the candidate position within the block,
`energy_old`, `energy_candidate`, and `overlap` are the mapped diagnostics,
and `detail` records the block mapping, `2J`, and parity. Both Ni fixtures have
J=0,1,2,3,4 blocks with 2,1,3,1,2 selected roots. Jobs 639/640/642 used incorrect
target indices; `3,4,7` select J=1,2,3 and omit J=4. Their Ni results also used
the faulty sparse-column build from Job 609 and are not physical baselines.
After an accepted row exchange, the guard carries the mapped row into the next
round while retaining the initial target index as its diagnostic label.  A
rejected candidate does not advance that mapping.

Job 643 confirmed that the corrected 46-rank initial CI is bit-for-bit equal in
energy to Job 631, but it reached 100 iterations without strict orbital
convergence.  Its all-new Ni I AS2 path is therefore regression evidence for
the sparse matrix and identity checks, not a converged physical baseline.

The sparse storage check calls the production `SPICMVmpi` and `INIESTmpi`
routines on a known 8x8 matrix packed into rank-local buffers. It checks matrix
products and packed entries against the dense matrix; the reduction is
replaced with a checked test seam, so this does not launch an MPI calculation:

```sh
ctest --test-dir build -R '^mpi90_local_sparse$' --output-on-failure
```

Guard thresholds are configured with `GRASP_MIN_ORBITAL_OVERLAP`,
`GRASP_MAX_RADIUS_RATIO`, `GRASP_REJECT_NODE_CHANGE`, and
`GRASP_MAX_REJECTS_PER_ORBITAL`. Expected-failure mode preserves the trace and
records the real MPI exit status in `rmcdhf.exitcode`.

Set `GRASP_RMCDHF_TIMEOUT` (for example `30m`) for tests that deliberately
exercise MPI failure paths. The runner uses GNU `timeout` to isolate the MPI
launcher in its own process group, sends TERM to the whole group at the limit,
and sends KILL after `GRASP_RMCDHF_KILL_AFTER` (default `30s`). A forced timeout
is recorded as exit status 124 and is accepted only when
`GRASP_EXPECT_RMCDHF_FAILURE=1` is also set.
For orbital-guard expected failures, `GRASP_ABORT_ON_ORBOPT_ERROR=1` additionally
terminates the launcher as soon as the rejection-limit marker appears in
`rmcdhf.stdout`, instead of waiting for the timeout.

An existing output directory is rejected to prevent accidental data loss.

## 后续测试参数约定

| 变量 | 作用 |
| --- | --- |
| `GRASP_ASF_SELECTION` | 覆盖 ASF 选择，多行值按各块顺序给出，用于 B8 状态集合对照 |
| `GRASP_ALLOW_RADIAL_GRID_DIFFERENCE=1` | 允许已记录的 `NNNP=2990` 与 `NNNP=590` 径向网格差异 |
| `GRASP_ALLOW_LEVEL_DIFFERENCES=1` | 允许 B8 改变状态集合，比较共有能级并报告独有能级 |

这些参数默认关闭，不改变历史计算流程。它们只影响测试输入或比较器，
不放宽 CSF 数量检查。B8 结果必须记录 `NNNP`、网格点数、ASF 选择、
共有/独有能级数量和最大共有能级能量差。
