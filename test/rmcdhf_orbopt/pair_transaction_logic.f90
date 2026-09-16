      PROGRAM PAIR_TRANSACTION_LOGIC
      USE vast_kind_param, ONLY: DOUBLE
      USE ORBOPT_PAIR_TYPES_C
      IMPLICIT NONE
      INTEGER, PARAMETER :: NMAX = 8
      INTEGER :: NP(NMAX), NAK(NMAX), IORDER(NMAX)
      INTEGER :: GROUP_SIZE(NMAX), GROUP_MEMBER(2,NMAX)
      INTEGER :: ORBITAL_GROUP(NMAX), GROUP_COUNT, STATUS
      LOGICAL :: LFIX(NMAX)
      CHARACTER(LEN=128) :: DETAIL
      REAL(DOUBLE) :: ENERGY_DELTA, DAMPING
      INTEGER :: STATUS_CASE

      NP = [4,1,2,3,5,6,7,8]
      NAK = -1
      IORDER = [(STATUS, STATUS=1,NMAX)]
      LFIX = .TRUE.

!     A varied s1/2 is the only legal singleton.
      NP(1) = 4
      NAK(1) = -1
      LFIX(1) = .FALSE.
      CALL BUILD_ORBITAL_GROUP_TABLE(NMAX, NP, NAK, LFIX, IORDER, &
           GROUP_COUNT, GROUP_SIZE, GROUP_MEMBER, ORBITAL_GROUP,  &
           STATUS, DETAIL)
      CALL ASSERT_TRUE(STATUS == PAIR_GROUP_OK, 's singleton status')
      CALL ASSERT_TRUE(GROUP_COUNT == 1, 's singleton count')
      CALL ASSERT_TRUE(GROUP_SIZE(1) == 1, 's singleton size')
      CALL ASSERT_TRUE(GROUP_MEMBER(1,1) == 1, 's singleton member')

!     First occurrence in IORDER sets group order; members are always
!     negative kappa followed by positive kappa.
      NP = [4,4,5,5,6,6,7,7]
      NAK = [-2,1,-3,2,-1,-2,1,-4]
      LFIX = .TRUE.
      LFIX(1:5) = .FALSE.
      IORDER = [4,3,2,1,5,6,7,8]
      CALL BUILD_ORBITAL_GROUP_TABLE(NMAX, NP, NAK, LFIX, IORDER, &
           GROUP_COUNT, GROUP_SIZE, GROUP_MEMBER, ORBITAL_GROUP,  &
           STATUS, DETAIL)
      CALL ASSERT_TRUE(STATUS == PAIR_GROUP_OK, 'ordered pairs status')
      CALL ASSERT_TRUE(GROUP_COUNT == 3, 'ordered pairs count')
      CALL ASSERT_TRUE(ALL(GROUP_MEMBER(:,1) == [3,4]), 'd pair order')
      CALL ASSERT_TRUE(ALL(GROUP_MEMBER(:,2) == [1,2]), 'p pair order')
      CALL ASSERT_TRUE(GROUP_MEMBER(1,3) == 5, 's group order')

!     Missing and fixed partners are rejected before SCF starts.
      LFIX(2) = .TRUE.
      CALL BUILD_ORBITAL_GROUP_TABLE(NMAX, NP, NAK, LFIX, IORDER, &
           GROUP_COUNT, GROUP_SIZE, GROUP_MEMBER, ORBITAL_GROUP,  &
           STATUS, DETAIL)
      CALL ASSERT_TRUE(STATUS == PAIR_GROUP_FIXED_PARTNER,        &
                       'fixed partner rejection')
      LFIX(2) = .FALSE.
      NAK(2) = -4
      CALL BUILD_ORBITAL_GROUP_TABLE(NMAX, NP, NAK, LFIX, IORDER, &
           GROUP_COUNT, GROUP_SIZE, GROUP_MEMBER, ORBITAL_GROUP,  &
           STATUS, DETAIL)
      CALL ASSERT_TRUE(STATUS == PAIR_GROUP_MISSING_PARTNER,      &
                       'missing partner rejection')

!     Invalid schedules, duplicate labels, and zero kappa are explicit
!     construction failures rather than ambiguous partial tables.
      NP = [4,4,5,5,6,6,7,7]
      NAK = [-2,1,-3,2,-1,-4,3,-5]
      LFIX = .TRUE.
      LFIX(1:2) = .FALSE.
      IORDER = [1,1,3,4,5,6,7,8]
      CALL BUILD_ORBITAL_GROUP_TABLE(NMAX, NP, NAK, LFIX, IORDER, &
           GROUP_COUNT, GROUP_SIZE, GROUP_MEMBER, ORBITAL_GROUP,  &
           STATUS_CASE, DETAIL)
      CALL ASSERT_TRUE(STATUS_CASE == PAIR_GROUP_BAD_ORDER,       &
                       'duplicate iorder rejection')
      IORDER = [(STATUS_CASE, STATUS_CASE=1,NMAX)]
      NP(2) = NP(1)
      NAK(2) = NAK(1)
      CALL BUILD_ORBITAL_GROUP_TABLE(NMAX, NP, NAK, LFIX, IORDER, &
           GROUP_COUNT, GROUP_SIZE, GROUP_MEMBER, ORBITAL_GROUP,  &
           STATUS_CASE, DETAIL)
      CALL ASSERT_TRUE(STATUS_CASE == PAIR_GROUP_DUPLICATE_ORBITAL, &
                       'duplicate orbital rejection')
      NAK(2) = 0
      CALL BUILD_ORBITAL_GROUP_TABLE(NMAX, NP, NAK, LFIX, IORDER, &
           GROUP_COUNT, GROUP_SIZE, GROUP_MEMBER, ORBITAL_GROUP,  &
           STATUS_CASE, DETAIL)
      CALL ASSERT_TRUE(STATUS_CASE == PAIR_GROUP_BAD_KAPPA,       &
                       'zero kappa rejection')

!     Retry damping follows the required 0.5 -> 0.7 -> 0.9 schedule.
      CALL ASSERT_CLOSE(RETRY_PAIR_DAMPING(1), 0.5D0, 'retry one')
      CALL ASSERT_CLOSE(RETRY_PAIR_DAMPING(2), 0.7D0, 'retry two')
      CALL ASSERT_CLOSE(RETRY_PAIR_DAMPING(3), 0.9D0, 'retry three')
      CALL ASSERT_CLOSE(RETRY_PAIR_DAMPING(9), 0.9D0, 'retry cap')

!     Constant damping is preserved; adaptive damping is bounded.
      DAMPING = SUGGEST_ORBITAL_DAMPING(-0.6D0, 0.D0, -2.D0,      &
           -1.9D0, 1.D0, 1.D-8, ENERGY_DELTA)
      CALL ASSERT_CLOSE(DAMPING, 0.6D0, 'constant damping')
      DAMPING = SUGGEST_ORBITAL_DAMPING(0.95D0, 0.1D0, -2.D0,     &
           -2.2D0, 1.D0, 1.D-8, ENERGY_DELTA)
      CALL ASSERT_TRUE(DAMPING <= 0.9D0, 'adaptive damping cap')
      DAMPING = SUGGEST_ORBITAL_DAMPING(0.4D0, 0.D0, -2.D0,       &
           -1.D0, 1.D0, 1.D-8, ENERGY_DELTA)
      CALL ASSERT_CLOSE(DAMPING, 0.3D0, 'adaptive initial visit')
      DAMPING = SUGGEST_ORBITAL_DAMPING(0.4D0, -0.2D0, -2.D0,     &
           -1.D0, 1.D0, 1.D-8, ENERGY_DELTA)
      CALL ASSERT_CLOSE(DAMPING, 0.3D0, 'adaptive same direction')
      DAMPING = SUGGEST_ORBITAL_DAMPING(0.4D0, 0.2D0, -2.D0,      &
           -1.D0, 1.D0, 1.D-8, ENERGY_DELTA)
      CALL ASSERT_CLOSE(DAMPING, 0.55D0, 'adaptive direction reversal')
      DAMPING = SUGGEST_ORBITAL_DAMPING(0.4D0, 0.2D0, -2.D0,      &
           -1.D0, 1.D-12, 1.D-8, ENERGY_DELTA)
      CALL ASSERT_CLOSE(DAMPING, 0.D0, 'converged damping')

      WRITE (*,'(A)') 'passed pair-transaction logic tests'

      CONTAINS

      SUBROUTINE ASSERT_TRUE(CONDITION, MESSAGE)
      LOGICAL, INTENT(IN) :: CONDITION
      CHARACTER(LEN=*), INTENT(IN) :: MESSAGE
      IF (.NOT.CONDITION) ERROR STOP MESSAGE
      END SUBROUTINE ASSERT_TRUE

      SUBROUTINE ASSERT_CLOSE(ACTUAL, EXPECTED, MESSAGE)
      REAL(DOUBLE), INTENT(IN) :: ACTUAL, EXPECTED
      CHARACTER(LEN=*), INTENT(IN) :: MESSAGE
      IF (ABS(ACTUAL-EXPECTED) > 1.D-12) ERROR STOP MESSAGE
      END SUBROUTINE ASSERT_CLOSE

      END PROGRAM PAIR_TRANSACTION_LOGIC
