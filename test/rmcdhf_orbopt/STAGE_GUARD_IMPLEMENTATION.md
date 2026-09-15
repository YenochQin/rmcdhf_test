# RMCDHF orbital-optimisation production gates

Implemented 2026-09-14.  This note separates what the archived jobs can prove
from the checks enforced for new active-space runs.

The production implementation has one source of truth under the paired
`graspkit-tools/scripts/grasp_regular_cal/` directory.  The generated
`mcdhfmpi.sh` calls `run_orbopt_stage.py` for each strictly increasing active
space.  The runner freezes CSF, previous accepted wave, isodata, case policy,
runtime controls, TF wave/baseline and a private copy of the controlled
`rmcdhf_mpi` executable into the immutable anchor.  The experimental
runner rejects a binary that does not advertise balanced-pair, round-rollback,
fixed-reference, and anchor-trace capabilities; it cannot silently use the
upstream module binary.  Runtime manifests also freeze the exact Thomas--Fermi
method number and required capability list.  Interrupted TF-baseline
publication is deterministically revalidated before RMCDHF may resume.  The
`run_data_case.sh` adapter imports that same guard instead of maintaining a
second transaction implementation.

## Runtime contract

`test/rmcdhf_orbopt/run_data_case.sh` now writes
`selection_manifest.json` before launching GRASP.  For every relativistic
subshell pair present in the actual `rcsf.inp`, selecting either member
requires selecting both.  An unbalanced list is rejected in production.
`GRASP_ALLOW_UNBALANCED=1` is the only override and records
`run_mode=diagnostic`, `allow_unbalanced=true`, the missing partners, and the
decision.  The executable independently receives
`GRASP_REQUIRE_BALANCED_PAIR=1` on the production path.  The existing
one-sided experiment scripts explicitly set the diagnostic override.

`GRASP_STAGE_TRANSACTION=1` enables the AS transaction.  It requires a case
acceptance JSON and an immutable RCI dialogue input.  The runner uses that
same dialogue, CSF list and Hamiltonian first on the exact TF `rwfn.inp` and
then on the accepted RMCDHF candidate wavefunction.  Interval acceptance is
therefore a matched fixed-RCI comparison, not an RMCDHF-vs-RCI comparison.
Before balanced RMCDHF starts, the TF fixed-RCI result must itself match each
target's LSJ/parity, dominant configuration/weight, and expected energy order.
A failure ends as `rejected_baseline` and selects the preceding accepted wave,
not the failed TF estimate; the TF wave, levels, and validation report remain
hash-frozen in the anchor for audit.
The transaction
creates immutable `anchor/`, mutable `candidate/`, and terminal `accepted/`
or `rejected/` areas.  `stage_manifest.json` records the state transitions,
anchor identity/hash, reason and chosen restart.  Only an accepted snapshot
writes `next_restart.json` pointing to `accepted/`; every candidate failure
after anchor verification points back to the anchor.  An anchor hash failure
publishes no restart at all.  Snapshot publication and pointer publication are
rollback tested with injected failures.

The Fortran trace can preserve the stage-start CI vectors with
`GRASP_FIXED_REFERENCE_PROXY=1`.  `round_target` rows now contain fixed target
labels, current rows, adjacent-round coefficient proxies, fixed-anchor
coefficient proxies, and per-block subspace minimum singular-value/maximum
principal-angle proxies, plus anchor ID/type/hash.  These are explicitly
same-CSF coefficient proxies.  Since orbitals change, they are not physical
many-electron ASF overlaps.  `GRASP_MIN_ANCHOR_SUBSPACE_PROXY` optionally
rejects cumulative drift; its default is diagnostic-only zero.

## Acceptance gates

A stage cannot be accepted unless all configured targets match exactly one
LSJ/parity row, retain the required dominant configuration and minimum
reference weight, retain the expected target ordering, satisfy strict SCF
convergence, pass any radial anchor proxy thresholds, and satisfy its physical
interval policy.  The Ni production fixture requires the optimized intervals
to be no worse than the matched TF/RCI baseline relative to NIST ASD values
1332.164 cm-1 (`3F3`) and 2216.550 cm-1 (`3F2`).  Missing target rules, a
failed TF baseline, a missing configured baseline, a missing TF radial anchor, a postprocessing
failure, or a hash mismatch is a rejection, not a skipped check.

## Offline audits and archived evidence

`audit_varied_lists.py` checked the actual RCSF orbital headers for Ni I,
Ni/Ca-like, Cl I and external Fe I.  Each legacy one-sided list is rejected in
production and accepted only with the diagnostic override; balanced lists pass
and no s orbital is falsely treated as requiring a partner.

`replay_stage_guard.py` replays only checks supported by archived artifacts:

| Job | Replay result | Reason |
|---|---|---|
| 645 | accepted by archived-evidence gates | strict two-step convergence, `3F4 < 3F3 < 3F2`, target weights 0.937/0.938/0.932 |
| 643 | rejected convergence/physics | strict convergence absent and final target ordering reversed |
| 609 | rejected identity | target weights 0.098/0.086/0.018 are below 0.85 |

Applying the new production interval policy to Job 645 using Job 635's TF
fixed-RCI result as the available counterfactual also rejects the candidate:
its `3F3` and `3F2` errors are 42.647 and 74.085 cm-1 versus the TF baseline's
27.102 and 48.536 cm-1.  The new runner improves this comparison further by
generating both fixed-RCI sides from the exact stage CSF, dialogue and wave
inputs instead of borrowing artifacts across jobs.

Jobs 601 and 602 both retain the correct dominant `3d8 3F 4s2` term and
ordering.  Their `3F3`/`3F2` intervals are 1375.865/2291.996 cm-1 and
1374.789/2290.415 cm-1 respectively.  This supports target-set consistency,
but it is not a fixed-TF comparison.

Job 635 provides the archived fixed-RCI counterexample: its Ni TF side has
the correct `3F4 < 3F3 < 3F2` ordering, while the optimized side reverses it.
There is no `fixed-orbital-rci-pair-636` directory in the supplied archive
(only 633--635 exist), so no Job 636 numerical result is claimed.  Historical
traces also lack the stage-start CI vector, so fixed-anchor coefficient values
are reported unavailable rather than reconstructed.  The new Job-645-equivalent
script `slurm/run_stage_guard_ni_46.sbatch` is the single required post-change
cluster run.  It verifies the new trace columns and accepts only a consistent
terminal transaction: either an accepted snapshot or a documented rejection
whose restart pointer returns to the immutable anchor.

Job 646 was the one permitted post-change submission.  It verified the input
gate, exact TF/fixed-RCI anchor construction, hash manifest, runtime-failure
classification, and rollback pointer: RMCDHF failed before creating a trace,
the stage ended as `rejected_runtime`, no `accepted/` snapshot was published,
and `next_restart.json` points to the immutable TF anchor.  The numerical run
did not start because the first implementation reused RMCDHF's `MPI_TMP` for
the serial fixed-RCI baseline, overwriting the 46-rank MCP files (`setmcp:
nblock = 0`).  The runner now gives every fixed-RCI side an isolated
`fixed_work/mpi_tmp`; in accordance with the one-submission rule this fix was
validated locally and Job 646 was not resubmitted.

## Validation

The implementation builds `rmcdhf_mpi`, adds the Python logic tests to CTest,
and covers sign flips, root swaps, subspace rotations, leakage, slow cumulative
drift, input selection, missing/empty artifacts, RMCDHF timeout, wrapper
failure, anchor tampering, and failures injected after snapshot/pointer
publication.

The paired Tools tests additionally execute a deterministic AS1 -> AS2
transaction without a cluster allocation.  They prove that AS2 accepts only
the hash-verified AS1 `accepted/` snapshot; changed runtime controls cannot
reuse an old terminal stage; malformed/unbalanced input, RMCDHF timeout,
postprocessing failures, fixed-target identity mismatches and publication
interruptions all end in a rejected state with `next_restart.json` pointing
to the immutable anchor.
