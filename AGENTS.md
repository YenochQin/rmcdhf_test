# Repository Guidelines

## Project Structure & Module Organization

GRASP is a Fortran 90/95 atomic-structure package. Sources live in `src/`:
`src/lib/` contains shared libraries (for example, `libmod` and `lib9290`),
`src/appl/` contains executable programs (including MPI variants), and
`src/tool/` contains supporting tools. Components have `CMakeLists.txt`,
`Makefile`, and Fortran `.f90` sources. CMake tests are under `test/`;
scientific examples and regression-style workflows are under
`grasptest/`. Built executables and archives are installed in `bin/` and `lib/`.

## Build, Test, and Development Commands

All Python helpers and tests use `../graspkit-tools/.venv`, created and synchronized
from Tools with its selected CPU/GPU extra. Activate it before Python tooling or
call its interpreter directly. Do not run `uv venv`, `uv sync`, or `uv run` here,
or create a local environment. The Fortran toolchain is configured separately.

Before configuring or compiling, initialize the host's compiler, BLAS/LAPACK, and
MPI toolchain. For Linux clusters using the documented Environment Modules setup:

```sh
source /usr/share/Modules/init/zsh
module load mpi/openmpi-x86_64
```

Use the cluster's actual initialization path and module names. On macOS or hosts
without Environment Modules, use the installed toolchain through `PATH` and CMake
settings. Keep compiler and BLAS/MPI choices consistent across comparison runs,
including serial targets; record differences when comparing across hosts.

Use an out-of-source CMake build:

```sh
./configure.sh --debug   # create build-debug/ with debug symbols
cmake --build build-debug -j4
ctest --test-dir build-debug -R rnucleus --output-on-failure
```

Select the CTest filter for the affected program. Install with `cmake --install build-debug`
when checking installed executables. Run `./configure.sh` without arguments for a
Release `build/` directory. Reuse an existing configured build when appropriate. CMake
requires a Fortran compiler plus BLAS/LAPACK; MPI targets are enabled only when
MPI Fortran is found. Its Fortran flags include `-fallow-argument-mismatch`,
which is required for legacy calls such as `lib9290/iniest2.f90` with modern
gfortran. Confirm CMake reports the intended `BLAS_LIBRARIES` and `LAPACK_LIBRARIES`.
Inspect linked libraries with `ldd` on Linux or `otool -L` on macOS; where a BLAS
dispatcher such as FlexiBLAS is used, also confirm its selected runtime backend.
Legacy `make`
builds in the source tree: use `make src/appl/rci90_mpi`; do not parallelize it.
Put compiler or linker overrides in untracked `Make.user`, never in `Makefile`.

## Coding Style & Naming Conventions

Write free-form Fortran in `.f90` files and match nearby indentation,
capitalization, and comments. Module sources commonly end in `_M.f90`,
interface/helper sources in `_I.f90`, and application directories use names
such as `rtransition90` or `rci90_mpi`. Update the component's build files when
adding a source. No formatter or linter configuration is enforced; avoid
unrelated reformatting.

## Testing Guidelines

Add or adjust CTest coverage for changed behavior in `test/CMakeLists.txt`.
Name tests by scope, e.g. `integration.rnucleus.Z1`, and keep test inputs in
the relevant `test/integration/` directory. Run the focused test with
`ctest --test-dir build -R rnucleus --output-on-failure`; expand to the full suite
for shared numerical code, libraries, or build changes. Documentation-only changes
need relevant link and command checks. Fix failures introduced by the change and
report remaining limitations; distinguish regression evidence from physical validation.

## Commit & Pull Request Guidelines

Use short, imperative commit subjects describing the affected program, such as
`Add CMakeLists.txt to jj2lsj program` or `Fix librang bounds check`. Reference
the related issue or PR when applicable (for example, `(#112)`). In pull
requests, explain the scientific or user-visible change, list the build/test
commands run, and call out compiler or MPI requirements. Include example
output or screenshots only when they clarify a changed tool or documentation.
