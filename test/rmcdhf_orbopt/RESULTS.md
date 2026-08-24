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

## Cl I AS1 B0--B6

The Cl I fixture was added under `test/data/Cl_I`.  The archived optimized
selection varies only the positive member of each relativistic pair.  Results
below use one MPI rank unless noted.

| Variant | Iterations | Ordering | Fine-structure interval (cm-1) | Minimum accepted overlap |
| --- | ---: | --- | ---: | ---: |
| B0 no-varied | 1 | J3/2 < J1/2 | 923.811587 | n/a |
| B1 positive only | 8 | J1/2 < J3/2 | -2479.507866 | 0.616734 |
| B2 minus only | 8 | J3/2 < J1/2 | 3788.603393 | 0.616734 |
| B3 balanced | 12 | J3/2 < J1/2 | 932.188187 | 0.558525 |
| B4 balanced, damping -0.5 | 21 | J3/2 < J1/2 | 932.184017 | 0.894903 |
| B5 deferred ORTHY | expected failure | non-finite at iteration 2 | n/a | n/a |
| B6 strict METHOD=3 | 12 | J3/2 < J1/2 | 932.188187 | 0.558525 |
| strict SCF | 35 | J3/2 < J1/2 | 932.190382 | 0.558525 |
| B8 equal EOL weights, damping -0.5 | 21 | J3/2 < J1/2 | 931.497237 | 0.897132 |

B4's independent RWFN cross-check matched 105 accepted updates.  Internal and
external overlap trends correlated at 0.996964; radius-factor trends correlated
at 0.989158.  B3 used METHOD=3 throughout and had no fallback, and B6 reproduced
B3 exactly.  Serial B3 and MPI B3 results were byte-identical.  B4 results with
MPI 1, 2, and 4 ranks were also byte-identical and produced no rank-summary
mismatch files.  Changing B4 from statistical to equal EOL weights changes the
interval by only -0.686780 cm-1 and does not alter the ordering or convergence
count, so the large B1 inversion is not explained by this weight choice.

## Cl I chained AS1--AS5

Each stage below starts from the preceding stage's newly accepted balanced,
damped wavefunction.  This avoids reintroducing the archived one-sided orbital
relaxation at every active-space boundary.

| Stage | Iterations | Interval (cm-1) | Minimum accepted overlap | Maximum radius factor | Accepted node-change events |
| --- | ---: | ---: | ---: | ---: | ---: |
| AS1 | 21 | 932.184017 | 0.894903 | 1.561 | 0 |
| AS2 | 20 | 930.990273 | 0.719901 | 2.195 | 5 |
| AS3 | 21 | 931.119697 | 0.712187 | 2.469 | 12 |
| AS4 | 27 | 931.148075 | 0.703857 | 2.713 | 20 |
| AS5 | 29 | 931.094852 | 0.699937 | 2.822 | 29 |

All five stages preserve `J3/2 < J1/2`, have no solver fallback, and show no
MPI rank-summary mismatch.  The interval is stable near 931 cm-1, whereas the
archived one-sided optimized sequence remains inverted from -1894.98 cm-1 at
AS2 to -1739.74 cm-1 at AS5.  Node counts still fluctuate from AS2 onward, so
the spectrum/order criterion passes but the final orbital-shape stability
criterion remains open.

## Comparison with NIST ASD levels

The NIST exports in `data/nist_levels` were matched by configuration, term,
parity, and J. Values below are intervals in cm-1; Ni I is referenced to
`3d8(3F)4s2 3F4`, and Ni IX (Ca-like) to `3p6 3d2 3F2`. Parentheses give
calculation minus NIST; negative intervals indicate inversion.

| Species / run | J2 | J3 | J4 | Ordering |
| --- | ---: | ---: | ---: | --- |
| Ni I NVaried AS1 | 2297.1 (+80.6) | 1378.7 (+46.5) | 0.0 (+0.0) | J4 < J3 < J2 |
| Ni I NVaried AS2 | 2303.9 (+87.3) | 1385.5 (+53.4) | 0.0 (+0.0) | J4 < J3 < J2 |
| Ni I optimized AS1 | -2734.4 (-4951.0) | -1419.6 (-2751.8) | 0.0 (+0.0) | J2 < J3 < J4 |
| Ni I optimized AS2 | -8440.3 (-10656.9) | -4196.5 (-5528.6) | 0.0 (+0.0) | J2 < J3 < J4 |
| Ni I optimized AS5 | -10132.7 (-12349.3) | -4932.5 (-6264.6) | 0.0 (+0.0) | J2 < J3 < J4 |
| Ni IX NVaried AS1 | 0.0 (+0.0) | 2021.6 (+141.6) | 4473.6 (+403.6) | J2 < J3 < J4 |
| Ni IX NVaried AS2 | 0.0 (+0.0) | 2020.9 (+140.9) | 4471.7 (+401.7) | J2 < J3 < J4 |
| Ni IX optimized AS1 | 0.0 (+0.0) | 590.0 (-1290.0) | 1287.2 (-2782.8) | J2 < J3 < J4 |
| Ni IX optimized AS2 | 0.0 (+0.0) | 68.1 (-1811.9) | 62.4 (-4007.6) | J2 < J4 < J3 |

NIST references are Ni I: J2=2216.550, J3=1332.164, J4=0.000; and
Ni IX: J2=0, J3=1880, J4=4070 cm-1. Fixed-orbital Ni I preserves the
ordering and is 46--87 cm-1 high, whereas one-sided optimization inverts it.
For Ni IX, fixed orbitals are within 142--404 cm-1; optimized AS1/AS2
degrade the splittings, with AS2 swapping J3/J4. Matching used the dominant
`3F` components listed in the corresponding `.uni.lsj.sum` files.
