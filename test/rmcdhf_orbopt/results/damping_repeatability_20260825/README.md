# Fixed-Damping Repeatability, 2026-08-25

Three complete fixed-damping matrices were run with explicit OpenMPI CPU
affinity on a 48-physical-core host.  Every case used four MPI ranks, twelve
OpenMP/BLAS threads per rank, and
`--map-by slot:PE=12 --bind-to core`; the four ranks therefore occupied
non-overlapping core sets 0--11, 12--23, 24--35, and 36--47.

All 27 RMCDHF executions exited with status zero.  Each of the three nine-case
matrices completed, no rank-summary mismatch file was produced, and all 18
comparisons of repeats 2 and 3 against repeat 1 matched exactly.  The maximum
absolute floating-point summary delta was zero; iteration counts, raw and
accepted node-change counts, fallback counts, and level ordering were also
identical.

The complete stdin, stdout, wavefunctions, and traces remain in the external
run directory `/tmp/rmcdhf-damping-repeats-pe12-20260825`.  Only the compact
comparison result is retained here.
