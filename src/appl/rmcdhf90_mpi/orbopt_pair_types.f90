!***********************************************************************
!  Data records and deterministic table construction for atomic
!  relativistic-partner updates.  This module deliberately has no MPI or
!  rmcdhf global-state dependency so its grouping rules can be unit tested.
!***********************************************************************
      MODULE ORBOPT_PAIR_TYPES_C
      USE vast_kind_param, ONLY: DOUBLE
      IMPLICIT NONE

      INTEGER, PARAMETER :: PAIR_GROUP_OK = 0
      INTEGER, PARAMETER :: PAIR_GROUP_BAD_ORDER = 1
      INTEGER, PARAMETER :: PAIR_GROUP_DUPLICATE_ORBITAL = 2
      INTEGER, PARAMETER :: PAIR_GROUP_BAD_KAPPA = 3
      INTEGER, PARAMETER :: PAIR_GROUP_MISSING_PARTNER = 4
      INTEGER, PARAMETER :: PAIR_GROUP_FIXED_PARTNER = 5

      TYPE ORBITAL_CANDIDATE_T
         INTEGER :: J = 0
         INTEGER :: MTP = 0
         INTEGER :: METHOD = 0
         INTEGER :: NSIC = 0
         INTEGER :: INV = 0
         INTEGER :: JP = 0
         INTEGER :: NNP = 0
         REAL(DOUBLE) :: ENERGY = 0.D0
         REAL(DOUBLE) :: P0 = 0.D0
         REAL(DOUBLE) :: SCNSTY = 0.D0
         REAL(DOUBLE) :: DNORM = 0.D0
         REAL(DOUBLE) :: NORM = 0.D0
         REAL(DOUBLE) :: OLD_NORM = 0.D0
         REAL(DOUBLE) :: OVERLAP = 0.D0
         REAL(DOUBLE) :: RADIUS_OLD = 0.D0
         REAL(DOUBLE) :: RADIUS_CANDIDATE = 0.D0
         REAL(DOUBLE) :: DAMPING_SUGGESTED = 0.D0
         REAL(DOUBLE) :: PED_PROPOSED = 0.D0
         INTEGER :: NODES_OLD = 0
         INTEGER :: NODES_CANDIDATE = 0
         LOGICAL :: SOLVE_FAILED = .FALSE.
         LOGICAL :: FALLBACK_REQUESTED = .FALSE.
         LOGICAL :: PREPARE_FAILED = .FALSE.
         CHARACTER(LEN=128) :: DETAIL = ''
         REAL(DOUBLE), ALLOCATABLE :: P(:)
         REAL(DOUBLE), ALLOCATABLE :: Q(:)
      END TYPE ORBITAL_CANDIDATE_T

      CONTAINS

      INTEGER FUNCTION ORBITAL_L(KAPPA)
      INTEGER, INTENT(IN) :: KAPPA
      IF (KAPPA > 0) THEN
         ORBITAL_L = KAPPA
      ELSE IF (KAPPA < 0) THEN
         ORBITAL_L = -KAPPA - 1
      ELSE
         ORBITAL_L = -1
      ENDIF
      END FUNCTION ORBITAL_L

      SUBROUTINE BUILD_ORBITAL_GROUP_TABLE(NW, NP, NAK, LFIX,      &
            IORDER, GROUP_COUNT, GROUP_SIZE, GROUP_MEMBER,         &
            ORBITAL_GROUP, STATUS, DETAIL)
!     Groups are ordered by the first occurrence of any member in IORDER.
!     Within l>0 groups the negative-kappa member precedes the positive one.
!     The s1/2 orbital (kappa=-1) is the only legal singleton.
      INTEGER, INTENT(IN) :: NW
      INTEGER, INTENT(IN) :: NP(:), NAK(:), IORDER(:)
      LOGICAL, INTENT(IN) :: LFIX(:)
      INTEGER, INTENT(OUT) :: GROUP_COUNT
      INTEGER, INTENT(OUT) :: GROUP_SIZE(:), GROUP_MEMBER(:,:)
      INTEGER, INTENT(OUT) :: ORBITAL_GROUP(:), STATUS
      CHARACTER(LEN=*), INTENT(OUT) :: DETAIL
      LOGICAL :: ORDER_SEEN(NW), ASSIGNED(NW)
      INTEGER :: POSITION, J, K, L, NEGATIVE_KAPPA, POSITIVE_KAPPA
      INTEGER :: NEGATIVE_MEMBER, POSITIVE_MEMBER
      INTEGER :: NEGATIVE_COUNT, POSITIVE_COUNT

      GROUP_COUNT = 0
      GROUP_SIZE = 0
      GROUP_MEMBER = 0
      ORBITAL_GROUP = 0
      STATUS = PAIR_GROUP_OK
      DETAIL = ''
      ORDER_SEEN = .FALSE.
      ASSIGNED = .FALSE.

!     IORDER must be a permutation.  A repeated or out-of-range index makes
!     first-occurrence group ordering ambiguous and is rejected explicitly.
      DO POSITION = 1, NW
         J = IORDER(POSITION)
         IF (J < 1 .OR. J > NW .OR. ORDER_SEEN(J)) THEN
            STATUS = PAIR_GROUP_BAD_ORDER
            DETAIL = 'invalid_or_duplicate_iorder'
            RETURN
         ENDIF
         ORDER_SEEN(J) = .TRUE.
      END DO

!     There can be only one radial orbital with a given (n,kappa) label.
      DO J = 1, NW
         IF (NAK(J) == 0) THEN
            STATUS = PAIR_GROUP_BAD_KAPPA
            DETAIL = 'zero_kappa'
            RETURN
         ENDIF
         DO K = J + 1, NW
            IF (NP(J) == NP(K) .AND. NAK(J) == NAK(K)) THEN
               STATUS = PAIR_GROUP_DUPLICATE_ORBITAL
               DETAIL = 'duplicate_n_kappa'
               RETURN
            ENDIF
         END DO
      END DO

      DO POSITION = 1, NW
         J = IORDER(POSITION)
         IF (LFIX(J) .OR. ASSIGNED(J)) CYCLE
         L = ORBITAL_L(NAK(J))
         IF (L < 0) THEN
            STATUS = PAIR_GROUP_BAD_KAPPA
            DETAIL = 'unknown_kappa'
            RETURN
         ENDIF

         GROUP_COUNT = GROUP_COUNT + 1
         IF (L == 0) THEN
            IF (NAK(J) /= -1) THEN
               STATUS = PAIR_GROUP_BAD_KAPPA
               DETAIL = 'invalid_s_kappa'
               RETURN
            ENDIF
            GROUP_SIZE(GROUP_COUNT) = 1
            GROUP_MEMBER(1,GROUP_COUNT) = J
            ORBITAL_GROUP(J) = GROUP_COUNT
            ASSIGNED(J) = .TRUE.
            CYCLE
         ENDIF

         NEGATIVE_KAPPA = -(L + 1)
         POSITIVE_KAPPA = L
         NEGATIVE_MEMBER = 0
         POSITIVE_MEMBER = 0
         NEGATIVE_COUNT = 0
         POSITIVE_COUNT = 0
         DO K = 1, NW
            IF (NP(K) /= NP(J)) CYCLE
            IF (NAK(K) == NEGATIVE_KAPPA) THEN
               NEGATIVE_COUNT = NEGATIVE_COUNT + 1
               IF (.NOT.LFIX(K)) NEGATIVE_MEMBER = K
            ELSE IF (NAK(K) == POSITIVE_KAPPA) THEN
               POSITIVE_COUNT = POSITIVE_COUNT + 1
               IF (.NOT.LFIX(K)) POSITIVE_MEMBER = K
            ENDIF
         END DO
         IF (NEGATIVE_COUNT /= 1 .OR. POSITIVE_COUNT /= 1) THEN
            STATUS = PAIR_GROUP_MISSING_PARTNER
            DETAIL = 'missing_or_duplicate_partner'
            RETURN
         ENDIF
         IF (NEGATIVE_MEMBER == 0 .OR. POSITIVE_MEMBER == 0) THEN
            STATUS = PAIR_GROUP_FIXED_PARTNER
            DETAIL = 'partner_is_fixed'
            RETURN
         ENDIF

         GROUP_SIZE(GROUP_COUNT) = 2
         GROUP_MEMBER(1,GROUP_COUNT) = NEGATIVE_MEMBER
         GROUP_MEMBER(2,GROUP_COUNT) = POSITIVE_MEMBER
         ORBITAL_GROUP(NEGATIVE_MEMBER) = GROUP_COUNT
         ORBITAL_GROUP(POSITIVE_MEMBER) = GROUP_COUNT
         ASSIGNED(NEGATIVE_MEMBER) = .TRUE.
         ASSIGNED(POSITIVE_MEMBER) = .TRUE.
      END DO

      DO J = 1, NW
         IF (.NOT.LFIX(J) .AND. ORBITAL_GROUP(J) == 0) THEN
            STATUS = PAIR_GROUP_MISSING_PARTNER
            DETAIL = 'varied_orbital_not_grouped'
            RETURN
         ENDIF
      END DO
      END SUBROUTINE BUILD_ORBITAL_GROUP_TABLE

      REAL(DOUBLE) FUNCTION SUGGEST_ORBITAL_DAMPING(OLD_DAMPING,   &
            PREVIOUS_ENERGY_DELTA, OLD_ENERGY, NEW_ENERGY,          &
            SELF_CONSISTENCY, ACCURACY, NEW_ENERGY_DELTA)
!     This is the adaptive rule used by rmcdhf_mpi DAMPCK, expressed
!     without hidden IPR state so both members can propose from one snapshot.
      REAL(DOUBLE), INTENT(IN) :: OLD_DAMPING, PREVIOUS_ENERGY_DELTA
      REAL(DOUBLE), INTENT(IN) :: OLD_ENERGY, NEW_ENERGY
      REAL(DOUBLE), INTENT(IN) :: SELF_CONSISTENCY, ACCURACY
      REAL(DOUBLE), INTENT(OUT) :: NEW_ENERGY_DELTA

!     The MPI DAMPCK keeps the absolute energy difference ED2-E(J), not the
!     relative signed rule used by the serial executable.
      NEW_ENERGY_DELTA = OLD_ENERGY - NEW_ENERGY
      IF (SELF_CONSISTENCY <= ACCURACY) THEN
         SUGGEST_ORBITAL_DAMPING = 0.D0
      ELSE IF (OLD_DAMPING < 0.D0) THEN
         SUGGEST_ORBITAL_DAMPING = ABS(OLD_DAMPING)
      ELSE IF (ABS(PREVIOUS_ENERGY_DELTA) <= TINY(1.D0)) THEN
!        No per-orbital history exists yet: match DAMPCK's IPR /= J path.
         SUGGEST_ORBITAL_DAMPING = 0.75D0*OLD_DAMPING
      ELSE IF (PREVIOUS_ENERGY_DELTA*NEW_ENERGY_DELTA > 0.D0) THEN
         SUGGEST_ORBITAL_DAMPING = 0.75D0*OLD_DAMPING
      ELSE
         SUGGEST_ORBITAL_DAMPING = 0.25D0 + 0.75D0*OLD_DAMPING
      ENDIF
      SUGGEST_ORBITAL_DAMPING = MAX(0.D0,                         &
                                    MIN(0.9D0, SUGGEST_ORBITAL_DAMPING))
      END FUNCTION SUGGEST_ORBITAL_DAMPING

      REAL(DOUBLE) FUNCTION RETRY_PAIR_DAMPING(RETRY_COUNT)
      INTEGER, INTENT(IN) :: RETRY_COUNT
      RETRY_PAIR_DAMPING = MIN(0.9D0, 0.5D0 +                     &
                               0.2D0*DBLE(MAX(0, RETRY_COUNT - 1)))
      END FUNCTION RETRY_PAIR_DAMPING

      END MODULE ORBOPT_PAIR_TYPES_C
