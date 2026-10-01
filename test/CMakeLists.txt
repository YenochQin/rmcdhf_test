# Make sure the test executables end up on build/test/, not build/bin/
# But we still need to know where the GRASP executables live, so we save that
# information first in a different variable.
set(BUILD_BINDIR ${CMAKE_RUNTIME_OUTPUT_DIRECTORY})
unset(CMAKE_RUNTIME_OUTPUT_DIRECTORY)

# Let's catch implicit uses of routines in the test prorams and libraries
set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -Werror=implicit-interface -Werror=implicit-procedure")

# Check lib92 routines -- this currently acts as a simple integration test,
# making sure that everything actually got compiled properly. The test checks
# that the QUAD routine from lib92 actually produces reasonable numbers.
add_executable(test.lib9290_quad
    lib9290_quad.f90
)
target_link_libraries_Fortran(test.lib9290_quad PUBLIC mod 9290)
add_test(lib9290_quad test.lib9290_quad)

if(MPI_Fortran_FOUND)
    # Calls the production sparse kernels with rank-local column buffers.
    # The test supplies a checked reduction seam, so no MPI job is launched.
    add_executable(test.mpi90_local_sparse mpi90_local_sparse.f90)
    target_link_libraries_Fortran(test.mpi90_local_sparse PUBLIC mpiu90 mod 9290)
    add_test(mpi90_local_sparse test.mpi90_local_sparse)
    set_tests_properties(mpi90_local_sparse PROPERTIES
        ENVIRONMENT "OMP_NUM_THREADS=1;OPENBLAS_NUM_THREADS=1")
endif()

# Pure grouping and retry-policy coverage for the production pair records.
add_executable(test.rmcdhf_pair_transaction_logic
    ../src/appl/rmcdhf90_mpi/orbopt_pair_types.f90
    rmcdhf_orbopt/pair_transaction_logic.f90
)
target_link_libraries_Fortran(test.rmcdhf_pair_transaction_logic PUBLIC mod)
add_test(NAME rmcdhf_pair_transaction_logic
    COMMAND test.rmcdhf_pair_transaction_logic)

find_package(Python3 COMPONENTS Interpreter)
if(Python3_Interpreter_FOUND)
    add_test(NAME rmcdhf_orbopt_round_state_logic
        COMMAND ${Python3_EXECUTABLE}
        ${CMAKE_CURRENT_SOURCE_DIR}/rmcdhf_orbopt/test_round_state_logic.py)
endif()

# Workspace Python tooling uses the single Tools environment, including this
# offline source-patcher test. Do not create a sibling Python environment.
if(WIN32)
    set(GRASP_GRID_TEST_PYTHON "${PROJECT_SOURCE_DIR}/../graspkit-tools/.venv/Scripts/python.exe")
else()
    set(GRASP_GRID_TEST_PYTHON "${PROJECT_SOURCE_DIR}/../graspkit-tools/.venv/bin/python")
endif()
if(EXISTS "${GRASP_GRID_TEST_PYTHON}")
    add_test(NAME grasp_grid_patcher
        COMMAND "${GRASP_GRID_TEST_PYTHON}"
        "${CMAKE_CURRENT_SOURCE_DIR}/test_patch_grasp_grid.py")
endif()
