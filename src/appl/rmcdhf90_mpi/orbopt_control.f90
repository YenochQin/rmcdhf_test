!***********************************************************************
!  Runtime controls for optional rmcdhf_mpi orbital-optimization
!  diagnostics.  All controls default to the historical behaviour.
!***********************************************************************
      MODULE ORBOPT_CONTROL_C
      USE vast_kind_param, ONLY: DOUBLE
      USE parameter_def, ONLY: NNNW
      USE mpi_C
      IMPLICIT NONE

      LOGICAL :: TRACE_ORBOPT = .FALSE.
      LOGICAL :: SAVE_RWFN_ITERATIONS = .FALSE.
      LOGICAL :: WARN_UNBALANCED_PAIR = .TRUE.
      LOGICAL :: REQUIRE_BALANCED_PAIR = .FALSE.
      LOGICAL :: ENABLE_ORBITAL_GUARD = .FALSE.
      LOGICAL :: GUARD_AFTER_DAMPING = .FALSE.
      LOGICAL :: STRICT_SCF_CONVERGENCE = .FALSE.
      LOGICAL :: DEFER_ORTHOGONALIZATION = .FALSE.
      LOGICAL :: STRICT_METHOD3 = .FALSE.
      LOGICAL :: TRACE_INITIAL_ORBITALS = .FALSE.
      INTEGER :: ORBOPT_TRACE_UNIT = 735
      INTEGER :: ORBOPT_ITERATION = 0
      CHARACTER(LEN=256) :: ORBOPT_TRACE_DIRECTORY = ''
      REAL(DOUBLE) :: FIXED_ORBITAL_DAMPING = 0.D0
      REAL(DOUBLE) :: MIN_ORBITAL_OVERLAP = 0.1D0
      REAL(DOUBLE) :: MAX_RADIUS_RATIO = 10.D0
      INTEGER :: MAX_REJECTS_PER_ORBITAL = 3
      LOGICAL :: REJECT_NODE_CHANGE = .TRUE.
      INTEGER :: ORBITAL_REJECT_COUNT(NNNW) = 0

      CONTAINS

      SUBROUTINE INIT_ORBOPT_CONTROL
      IF (myid == 0) THEN
         CALL READ_LOGICAL_ENV('GRASP_TRACE_ORBOPT', TRACE_ORBOPT)
         CALL READ_LOGICAL_ENV('GRASP_TRACE_RWFN',                   &
                               SAVE_RWFN_ITERATIONS)
         CALL READ_LOGICAL_ENV('GRASP_REQUIRE_BALANCED_PAIR',       &
                               REQUIRE_BALANCED_PAIR)
         CALL READ_LOGICAL_ENV('GRASP_ORBITAL_GUARD',               &
                               ENABLE_ORBITAL_GUARD)
         CALL READ_LOGICAL_ENV('GRASP_GUARD_AFTER_DAMPING',         &
                               GUARD_AFTER_DAMPING)
         CALL READ_LOGICAL_ENV('GRASP_STRICT_SCF',                  &
                               STRICT_SCF_CONVERGENCE)
         CALL READ_LOGICAL_ENV('GRASP_DEFER_ORTHY',                 &
                               DEFER_ORTHOGONALIZATION)
         CALL READ_LOGICAL_ENV('GRASP_STRICT_METHOD3', STRICT_METHOD3)
         CALL READ_LOGICAL_ENV('GRASP_TRACE_INITIAL_ORBITALS', TRACE_INITIAL_ORBITALS)
         CALL READ_REAL_ENV('GRASP_ORBITAL_DAMPING',                &
                            FIXED_ORBITAL_DAMPING)
         CALL READ_REAL_ENV('GRASP_MIN_ORBITAL_OVERLAP',            &
                            MIN_ORBITAL_OVERLAP)
         CALL READ_REAL_ENV('GRASP_MAX_RADIUS_RATIO',               &
                            MAX_RADIUS_RATIO)
         CALL READ_INTEGER_ENV('GRASP_MAX_REJECTS_PER_ORBITAL',     &
                               MAX_REJECTS_PER_ORBITAL)
         CALL READ_LOGICAL_ENV('GRASP_REJECT_NODE_CHANGE',          &
                               REJECT_NODE_CHANGE)

         IF (FIXED_ORBITAL_DAMPING /= 0.D0 .AND.                   &
             (FIXED_ORBITAL_DAMPING <= -1.D0 .OR.                  &
              FIXED_ORBITAL_DAMPING >= 0.D0)) THEN
            WRITE (*,'(A)') 'ORBOPT: GRASP_ORBITAL_DAMPING must be'//&
                             ' in (-1,0); disabling fixed damping'
            FIXED_ORBITAL_DAMPING = 0.D0
         ENDIF
         IF (MIN_ORBITAL_OVERLAP < 0.D0 .OR.                       &
             MIN_ORBITAL_OVERLAP > 1.D0) THEN
            WRITE (*,'(A)') 'ORBOPT: overlap threshold must be in'//&
                             ' [0,1]; using 0.1'
            MIN_ORBITAL_OVERLAP = 0.1D0
         ENDIF
         IF (MAX_RADIUS_RATIO < 1.D0) THEN
            WRITE (*,'(A)') 'ORBOPT: radius ratio must be >= 1;'//  &
                             ' using 10'
            MAX_RADIUS_RATIO = 10.D0
         ENDIF
         IF (MAX_REJECTS_PER_ORBITAL < 1) THEN
            WRITE (*,'(A)') 'ORBOPT: max rejects must be positive;'//&
                             ' using 3'
            MAX_REJECTS_PER_ORBITAL = 3
         ENDIF
      ENDIF

      CALL MPI_Bcast(TRACE_ORBOPT, 1, MPI_LOGICAL, 0,               &
                     MPI_COMM_WORLD, ierr)
      CALL MPI_Bcast(SAVE_RWFN_ITERATIONS, 1, MPI_LOGICAL, 0,       &
                     MPI_COMM_WORLD, ierr)
      CALL MPI_Bcast(REQUIRE_BALANCED_PAIR, 1, MPI_LOGICAL, 0,      &
                     MPI_COMM_WORLD, ierr)
      CALL MPI_Bcast(ENABLE_ORBITAL_GUARD, 1, MPI_LOGICAL, 0,       &
                     MPI_COMM_WORLD, ierr)
      CALL MPI_Bcast(GUARD_AFTER_DAMPING, 1, MPI_LOGICAL, 0,       &
                     MPI_COMM_WORLD, ierr)
      CALL MPI_Bcast(STRICT_SCF_CONVERGENCE, 1, MPI_LOGICAL, 0,     &
                     MPI_COMM_WORLD, ierr)
      CALL MPI_Bcast(DEFER_ORTHOGONALIZATION, 1, MPI_LOGICAL, 0,    &
                     MPI_COMM_WORLD, ierr)
      CALL MPI_Bcast(STRICT_METHOD3, 1, MPI_LOGICAL, 0,             &
                     MPI_COMM_WORLD, ierr)
      CALL MPI_Bcast(TRACE_INITIAL_ORBITALS, 1, MPI_LOGICAL, 0,    &
                     MPI_COMM_WORLD, ierr)
      CALL MPI_Bcast(FIXED_ORBITAL_DAMPING, 1,                     &
                     MPI_DOUBLE_PRECISION, 0, MPI_COMM_WORLD, ierr)
      CALL MPI_Bcast(MIN_ORBITAL_OVERLAP, 1, MPI_DOUBLE_PRECISION, &
                     0, MPI_COMM_WORLD, ierr)
      CALL MPI_Bcast(MAX_RADIUS_RATIO, 1, MPI_DOUBLE_PRECISION, 0, &
                     MPI_COMM_WORLD, ierr)
      CALL MPI_Bcast(MAX_REJECTS_PER_ORBITAL, 1, MPI_INTEGER, 0,   &
                     MPI_COMM_WORLD, ierr)
      CALL MPI_Bcast(REJECT_NODE_CHANGE, 1, MPI_LOGICAL, 0,        &
                     MPI_COMM_WORLD, ierr)
      ORBITAL_REJECT_COUNT = 0

      IF (myid == 0 .AND. (TRACE_ORBOPT .OR. SAVE_RWFN_ITERATIONS .OR. &
          REQUIRE_BALANCED_PAIR .OR. ENABLE_ORBITAL_GUARD .OR.     &
          GUARD_AFTER_DAMPING .OR.                                  &
          STRICT_SCF_CONVERGENCE .OR. DEFER_ORTHOGONALIZATION .OR. &
          STRICT_METHOD3)) THEN
         WRITE (*,'(A,8(1X,L1))') 'ORBOPT controls:',               &
            TRACE_ORBOPT, REQUIRE_BALANCED_PAIR,                   &
            ENABLE_ORBITAL_GUARD, GUARD_AFTER_DAMPING,              &
            STRICT_SCF_CONVERGENCE,                                 &
            SAVE_RWFN_ITERATIONS, DEFER_ORTHOGONALIZATION,         &
            STRICT_METHOD3
      ENDIF
      IF (myid == 0 .AND. (FIXED_ORBITAL_DAMPING /= 0.D0 .OR.     &
                           ENABLE_ORBITAL_GUARD)) THEN
         WRITE (*,'(A,3(1X,ES10.3),1X,I0,1X,L1)')                  &
            'ORBOPT damping/guard:', FIXED_ORBITAL_DAMPING,        &
            MIN_ORBITAL_OVERLAP, MAX_RADIUS_RATIO,                 &
            MAX_REJECTS_PER_ORBITAL, REJECT_NODE_CHANGE
      ENDIF
      END SUBROUTINE INIT_ORBOPT_CONTROL

      SUBROUTINE APPLY_FIXED_ORBITAL_DAMPING(NW, LFIX, ODAMP)
      INTEGER, INTENT(IN) :: NW
      LOGICAL, INTENT(IN) :: LFIX(*)
      REAL(DOUBLE), INTENT(INOUT) :: ODAMP(*)
      INTEGER :: I
      IF (FIXED_ORBITAL_DAMPING == 0.D0) RETURN
      DO I = 1, NW
         IF (.NOT.LFIX(I)) ODAMP(I) = FIXED_ORBITAL_DAMPING
      END DO
      END SUBROUTINE APPLY_FIXED_ORBITAL_DAMPING

      SUBROUTINE RECORD_ORBITAL_REJECTION(J, COUNT, EXCEEDED)
      INTEGER, INTENT(IN) :: J
      INTEGER, INTENT(OUT) :: COUNT
      LOGICAL, INTENT(OUT) :: EXCEEDED
      ORBITAL_REJECT_COUNT(J) = ORBITAL_REJECT_COUNT(J) + 1
      COUNT = ORBITAL_REJECT_COUNT(J)
      EXCEEDED = COUNT > MAX_REJECTS_PER_ORBITAL
      END SUBROUTINE RECORD_ORBITAL_REJECTION

      SUBROUTINE CLEAR_ORBITAL_REJECTIONS(J)
      INTEGER, INTENT(IN) :: J
      ORBITAL_REJECT_COUNT(J) = 0
      END SUBROUTINE CLEAR_ORBITAL_REJECTIONS

      SUBROUTINE SET_ORBOPT_ITERATION(NIT)
      INTEGER, INTENT(IN) :: NIT
      ORBOPT_ITERATION = NIT
      END SUBROUTINE SET_ORBOPT_ITERATION

      SUBROUTINE SET_ORBOPT_TRACE_DIRECTORY(DIRECTORY)
      CHARACTER(LEN=*), INTENT(IN) :: DIRECTORY
      ORBOPT_TRACE_DIRECTORY = TRIM(DIRECTORY)
      END SUBROUTINE SET_ORBOPT_TRACE_DIRECTORY

      SUBROUTINE READ_LOGICAL_ENV(NAME, FLAG)
      CHARACTER(LEN=*), INTENT(IN) :: NAME
      LOGICAL, INTENT(INOUT) :: FLAG
      CHARACTER(LEN=32) :: VALUE
      INTEGER :: LENGTH, STATUS

      CALL GET_ENVIRONMENT_VARIABLE(NAME, VALUE, LENGTH, STATUS)
      IF (STATUS /= 0 .OR. LENGTH == 0) RETURN

      SELECT CASE (VALUE(:LENGTH))
      CASE ('1', 'true', 'TRUE', 'yes', 'YES', 'on', 'ON')
         FLAG = .TRUE.
      CASE ('0', 'false', 'FALSE', 'no', 'NO', 'off', 'OFF')
         FLAG = .FALSE.
      CASE DEFAULT
         WRITE (*,'(A,1X,A,1X,A)') 'ORBOPT: ignoring invalid value for', &
            NAME, VALUE(:LENGTH)
      END SELECT
      END SUBROUTINE READ_LOGICAL_ENV

      SUBROUTINE READ_REAL_ENV(NAME, VALUE_OUT)
      CHARACTER(LEN=*), INTENT(IN) :: NAME
      REAL(DOUBLE), INTENT(INOUT) :: VALUE_OUT
      CHARACTER(LEN=64) :: VALUE
      INTEGER :: LENGTH, STATUS, IO_STATUS
      REAL(DOUBLE) :: PARSED
      CALL GET_ENVIRONMENT_VARIABLE(NAME, VALUE, LENGTH, STATUS)
      IF (STATUS /= 0 .OR. LENGTH == 0) RETURN
      READ (VALUE(:LENGTH),*,IOSTAT=IO_STATUS) PARSED
      IF (IO_STATUS == 0) THEN
         VALUE_OUT = PARSED
      ELSE
         WRITE (*,'(A,1X,A)') 'ORBOPT: ignoring invalid real', NAME
      ENDIF
      END SUBROUTINE READ_REAL_ENV

      SUBROUTINE READ_INTEGER_ENV(NAME, VALUE_OUT)
      CHARACTER(LEN=*), INTENT(IN) :: NAME
      INTEGER, INTENT(INOUT) :: VALUE_OUT
      CHARACTER(LEN=64) :: VALUE
      INTEGER :: LENGTH, STATUS, IO_STATUS, PARSED
      CALL GET_ENVIRONMENT_VARIABLE(NAME, VALUE, LENGTH, STATUS)
      IF (STATUS /= 0 .OR. LENGTH == 0) RETURN
      READ (VALUE(:LENGTH),*,IOSTAT=IO_STATUS) PARSED
      IF (IO_STATUS == 0) THEN
         VALUE_OUT = PARSED
      ELSE
         WRITE (*,'(A,1X,A)') 'ORBOPT: ignoring invalid integer', NAME
      ENDIF
      END SUBROUTINE READ_INTEGER_ENV

      END MODULE ORBOPT_CONTROL_C
