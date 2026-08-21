# AS2 B2/B3 Diagnostic Results

Runs used the archived AS2 CSF inputs, preceding-stage wavefunctions, current
`build-debug/bin/rmcdhf_mpi`, and `mpi/openmpi-x86_64`. B1 is the original
positive-member selection, B2 selects minus members, and B3 selects both
relativistic partners. NV fixes every new orbital.

| Case | SCF iterations | Minimum overlap | Max radius factor | Node changes | J ordering |
| --- | ---: | ---: | ---: | ---: | --- |
| Ni I NV | 1 | n/a | n/a | 0 | J4 < J3 < J2 |
| Ni I B1 | 20 | 0.02920 | 8.610 | 2 | J2 < J3 < J4 |
| Ni I B2 | 12 | 0.03570 | 8.416 | 1 | J4 < J3 < J2 |
| Ni I B3 | 14 | 0.02902 | 8.630 | 3 | J4 < J3 < J2 |
| Ni/Ca-like NV | 1 | n/a | n/a | 0 | J2 < J3 < J4 |
| Ni/Ca-like B1 | 6 | 0.19329 | 2.781 | 0 | J2 < J4 < J3 |
| Ni/Ca-like B2 | 7 | 0.29918 | 2.784 | 0 | J2 < J3 < J4 |
| Ni/Ca-like B3 | 8 | 0.18857 | 2.798 | 0 | J2 < J3 < J4 |

## B4 Fixed Damping and Guard

With `GRASP_ORBITAL_DAMPING=-0.5`, the raw candidates remain unchanged in
quality, but the orbitals actually accepted after `DAMPOR` are substantially
smoother:

| Case | Iterations | Raw overlap/radius | Accepted overlap/radius | Accepted node changes | J ordering |
| --- | ---: | --- | --- | ---: | --- |
| Ni I B3+B4 | 29 | 0.02847 / 8.588 | 0.71710 / 1.824 | 0 | J4 < J3 < J2 |
| Ni/Ca-like B3+B4+guard | 17 | 0.19559 / 2.789 | 0.77317 / 1.558 | 0 | J2 < J3 < J4 |

The Ni/Ca-like guard run used the default overlap threshold of 0.1 and
completed without rejection. A Ni I guard run rejected `6s`, `5d`, `4f-`,
and `4f`; with a rejection limit of two it stopped explicitly on the third
`6s` rejection instead of accepting the candidate or reporting convergence.
The next proposed damping values were recorded as 0.5, 0.7, and 0.9.

A recovery experiment with overlap threshold 0.03 showed that an unchanged
rejected `4f` candidate did not recover: its overlap decreased from 0.02847 to
0.02452 over six attempts. This is an important limitation of guarding the
raw candidate before `DAMPOR`: strict rejection can block a damped update that
would itself be stable. The guard therefore remains disabled by default and
must not yet be enabled as a production policy.

The fastest tested configuration on the 48-core reference host was four MPI
ranks with 12 OpenMP threads per rank. Pure 24-rank MPI was communication
bound, while forcing every rank to one thread underused threaded BLAS.

All runs completed without solver fallback. B3 removed the unbalanced-pair
warnings and restored the expected J ordering, but did not remove the large
first-iteration radial changes. Ni I B3 retained overlaps below 0.1 and node
changes. Pair completeness therefore affects fine-structure ordering, but is
not sufficient to make candidate orbitals stable; damping/guard experiments
show that fixed damping stabilizes accepted updates. Automatic pair expansion
and strict raw-candidate guarding must both remain disabled by default.
