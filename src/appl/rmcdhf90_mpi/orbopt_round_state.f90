!***********************************************************************
!  Optional SCF-round transaction for orbital optimisation.
!  The historical path is unchanged unless GRASP_ROUND_ROLLBACK_GUARD=1.
!***********************************************************************
      MODULE ORBOPT_ROUND_STATE_C
      USE vast_kind_param, ONLY: DOUBLE
      USE parameter_def, ONLY: NNNP, NNNW
      USE def_C, ONLY: ICCMIN, NCMIN, NSIC, WT
      USE eigv_C, ONLY: EAV, EVAL, EVEC
      USE hblock_C, ONLY: NBLOCK, NCFBLK, NEVBLK
      USE peav_C, ONLY: EAVBLK
      USE pos_C, ONLY: NCFTOT, NVECSIZ, NCFPAST, NCMINPAST, NEVECPAST
      USE orb_C, ONLY: E, NW
      USE wave_C, ONLY: MF, PF, PZ, QF
      USE scf_C, ONLY: METHOD, SCNSTY, UCF
      USE damp_C, ONLY: ODAMP
      USE int_C, ONLY: MTP0
      USE tatb_C, ONLY: MTP
      USE fixd_C, ONLY: LFIX
      USE syma_C, ONLY: IATJPO, IASPAR, JPGG
      USE ORBOPT_CONTROL_C, ONLY: ROUND_ROLLBACK_GUARD,          &
            ROUND_REJECT_ENERGY_ORDER, MIN_STATE_OVERLAP,          &
            TARGET_STATE_COUNT, TARGET_STATE_INDEX
      IMPLICIT NONE

      LOGICAL :: ROUND_STATE_ACTIVE = .FALSE.
      INTEGER :: ROUND_ROLLBACK_COUNT = 0
      INTEGER, ALLOCATABLE :: ROUND_ASSIGNMENT(:)
      INTEGER, ALLOCATABLE :: ROUND_TARGET_CURRENT(:)
      INTEGER, ALLOCATABLE :: ROUND_TARGET_ACCEPTED(:)
      INTEGER, ALLOCATABLE :: ROUND_TARGET_BLOCK(:)
      INTEGER, ALLOCATABLE :: ROUND_TARGET_POSITION(:)
      REAL(DOUBLE), ALLOCATABLE :: ROUND_TARGET_OVERLAP(:)
      REAL(DOUBLE), ALLOCATABLE :: ROUND_TARGET_OLD_ENERGY(:)
      REAL(DOUBLE), ALLOCATABLE :: ROUND_TARGET_NEW_ENERGY(:)

      REAL(DOUBLE), ALLOCATABLE :: PF_SAVE(:,:), QF_SAVE(:,:)
      REAL(DOUBLE), ALLOCATABLE :: EVAL_SAVE(:), EVEC_SAVE(:)
      REAL(DOUBLE), ALLOCATABLE :: EAVBLK_SAVE(:), WT_SAVE(:)
      REAL(DOUBLE), ALLOCATABLE :: E_SAVE(:), PZ_SAVE(:), UCF_SAVE(:)
      REAL(DOUBLE), ALLOCATABLE :: SCNSTY_SAVE(:), ODAMP_SAVE(:)
      INTEGER, ALLOCATABLE :: MF_SAVE(:), METHOD_SAVE(:)
      INTEGER, ALLOCATABLE :: ICCMIN_SAVE(:), IATJPO_SAVE(:), IASPAR_SAVE(:)
      REAL(DOUBLE) :: EAV_SAVE
      INTEGER :: MTP0_SAVE, MTP_SAVE, NSIC_SAVE

      CONTAINS

      SUBROUTINE BEGIN_ORBOPT_ROUND(EOL)
      LOGICAL, INTENT(IN) :: EOL
      INTEGER :: IOS

      IF (.NOT.ROUND_ROLLBACK_GUARD .OR. .NOT.EOL) RETURN
      CALL RELEASE_ROUND_STORAGE()
      IF (.NOT.ASSOCIATED(PF) .OR. .NOT.ASSOCIATED(QF)) RETURN
      IF (.NOT.ASSOCIATED(EVAL) .OR. .NOT.ASSOCIATED(EVEC)) RETURN

      ALLOCATE(PF_SAVE(NNNP,NW), QF_SAVE(NNNP,NW), STAT=IOS)
      IF (IOS /= 0) ERROR STOP 'ORBOPT: round snapshot allocation failed'
      ALLOCATE(EVAL_SAVE(NCMIN), EVEC_SAVE(NVECSIZ),               &
               EAVBLK_SAVE(NBLOCK), WT_SAVE(NCMIN), STAT=IOS)
      IF (IOS /= 0) ERROR STOP 'ORBOPT: CI snapshot allocation failed'
      ALLOCATE(ICCMIN_SAVE(NCMIN), IATJPO_SAVE(NCMIN),             &
               IASPAR_SAVE(NCMIN), STAT=IOS)
      IF (IOS /= 0) ERROR STOP 'ORBOPT: CI identity snapshot allocation failed'
      ALLOCATE(E_SAVE(NNNW), PZ_SAVE(NNNW), UCF_SAVE(NNNW),        &
               SCNSTY_SAVE(NNNW), ODAMP_SAVE(NNNW),               &
               MF_SAVE(NNNW), METHOD_SAVE(NNNW), STAT=IOS)
      IF (IOS /= 0) ERROR STOP 'ORBOPT: orbital snapshot allocation failed'

      PF_SAVE = PF
      QF_SAVE = QF
      EVAL_SAVE = EVAL
      EVEC_SAVE = EVEC
      EAVBLK_SAVE = EAVBLK
      WT_SAVE = WT
      ICCMIN_SAVE = ICCMIN
      IATJPO_SAVE = IATJPO
      IASPAR_SAVE = IASPAR
      E_SAVE = E
      PZ_SAVE = PZ
      UCF_SAVE = UCF
      SCNSTY_SAVE = SCNSTY
      ODAMP_SAVE = ODAMP
      MF_SAVE = MF
      METHOD_SAVE = METHOD
      EAV_SAVE = EAV
      MTP0_SAVE = MTP0
      MTP_SAVE = MTP
      NSIC_SAVE = NSIC
      ROUND_STATE_ACTIVE = .TRUE.
      END SUBROUTINE BEGIN_ORBOPT_ROUND

      SUBROUTINE ACCEPT_ORBOPT_ROUND
!     Carry physical target identities through an accepted root exchange.
!     TARGET_STATE_INDEX identifies each target in the initial CI ordering;
!     ROUND_TARGET_ACCEPTED records where that same target resides in the
!     current, energy-sorted EVEC array.  Rejected candidates never update it.
      INTEGER :: IOS

      IF (.NOT.ROUND_STATE_ACTIVE .OR. TARGET_STATE_COUNT <= 0) RETURN
      IF (.NOT.ALLOCATED(ROUND_TARGET_CURRENT)) RETURN
      IF (.NOT.ALLOCATED(ROUND_TARGET_ACCEPTED)) THEN
         ALLOCATE(ROUND_TARGET_ACCEPTED(TARGET_STATE_COUNT), STAT=IOS)
         IF (IOS /= 0) ERROR STOP 'ORBOPT: persistent target allocation failed'
      ENDIF
      ROUND_TARGET_ACCEPTED = ROUND_TARGET_CURRENT
      END SUBROUTINE ACCEPT_ORBOPT_ROUND

      SUBROUTINE CHECK_ORBOPT_ROUND(BAD, MIN_OVERLAP,             &
            ORDER_CHANGED, NONIDENTITY, DETAIL)
      LOGICAL, INTENT(OUT) :: BAD, ORDER_CHANGED, NONIDENTITY
      REAL(DOUBLE), INTENT(OUT) :: MIN_OVERLAP
      CHARACTER(LEN=*), INTENT(OUT) :: DETAIL

      BAD = .FALSE.
      ORDER_CHANGED = .FALSE.
      NONIDENTITY = .FALSE.
      MIN_OVERLAP = 1.D0
      DETAIL = ''
      IF (.NOT.ROUND_STATE_ACTIVE) RETURN

      CALL CHECK_VECTOR_OVERLAP(MIN_OVERLAP, NONIDENTITY)
      CALL CHECK_TARGET_ENERGY_ORDER(ORDER_CHANGED)

      IF (ROUND_REJECT_ENERGY_ORDER .AND. TARGET_STATE_COUNT > 1 .AND. &
          ORDER_CHANGED) THEN
         BAD = .TRUE.
         DETAIL = 'energy_order'
      ENDIF
      IF (MIN_OVERLAP < MIN_STATE_OVERLAP) THEN
         BAD = .TRUE.
         IF (LEN_TRIM(DETAIL) > 0) DETAIL = TRIM(DETAIL)//'+'
         DETAIL = TRIM(DETAIL)//'state_overlap'
      ENDIF
      END SUBROUTINE CHECK_ORBOPT_ROUND

      SUBROUTINE RESTORE_ORBOPT_ROUND
      INTEGER :: I
      REAL(DOUBLE) :: DAMPING

      IF (.NOT.ROUND_STATE_ACTIVE) RETURN
      PF = PF_SAVE
      QF = QF_SAVE
      EVAL = EVAL_SAVE
      EVEC = EVEC_SAVE
      EAVBLK = EAVBLK_SAVE
      WT = WT_SAVE
      ICCMIN = ICCMIN_SAVE
      IATJPO = IATJPO_SAVE
      IASPAR = IASPAR_SAVE
      E = E_SAVE
      PZ = PZ_SAVE
      UCF = UCF_SAVE
      SCNSTY = SCNSTY_SAVE
      ODAMP = ODAMP_SAVE
      MF = MF_SAVE
      METHOD = METHOD_SAVE
      EAV = EAV_SAVE
      MTP0 = MTP0_SAVE
      MTP = MTP_SAVE
      NSIC = NSIC_SAVE

      ROUND_ROLLBACK_COUNT = ROUND_ROLLBACK_COUNT + 1
      DAMPING = MIN(0.9D0, 0.5D0 +                             &
                    0.2D0*DBLE(ROUND_ROLLBACK_COUNT - 1))
      DO I = 1, NW
         IF (.NOT.LFIX(I)) ODAMP(I) = -DAMPING
      END DO
      END SUBROUTINE RESTORE_ORBOPT_ROUND

      SUBROUTINE RELEASE_ROUND_STORAGE
      IF (ALLOCATED(PF_SAVE)) DEALLOCATE(PF_SAVE)
      IF (ALLOCATED(QF_SAVE)) DEALLOCATE(QF_SAVE)
      IF (ALLOCATED(EVAL_SAVE)) DEALLOCATE(EVAL_SAVE)
      IF (ALLOCATED(EVEC_SAVE)) DEALLOCATE(EVEC_SAVE)
      IF (ALLOCATED(EAVBLK_SAVE)) DEALLOCATE(EAVBLK_SAVE)
      IF (ALLOCATED(WT_SAVE)) DEALLOCATE(WT_SAVE)
      IF (ALLOCATED(ICCMIN_SAVE)) DEALLOCATE(ICCMIN_SAVE)
      IF (ALLOCATED(IATJPO_SAVE)) DEALLOCATE(IATJPO_SAVE)
      IF (ALLOCATED(IASPAR_SAVE)) DEALLOCATE(IASPAR_SAVE)
      IF (ALLOCATED(E_SAVE)) DEALLOCATE(E_SAVE)
      IF (ALLOCATED(PZ_SAVE)) DEALLOCATE(PZ_SAVE)
      IF (ALLOCATED(UCF_SAVE)) DEALLOCATE(UCF_SAVE)
      IF (ALLOCATED(SCNSTY_SAVE)) DEALLOCATE(SCNSTY_SAVE)
      IF (ALLOCATED(ODAMP_SAVE)) DEALLOCATE(ODAMP_SAVE)
      IF (ALLOCATED(MF_SAVE)) DEALLOCATE(MF_SAVE)
      IF (ALLOCATED(METHOD_SAVE)) DEALLOCATE(METHOD_SAVE)
      IF (ALLOCATED(ROUND_ASSIGNMENT)) DEALLOCATE(ROUND_ASSIGNMENT)
      IF (ALLOCATED(ROUND_TARGET_CURRENT)) DEALLOCATE(ROUND_TARGET_CURRENT)
      IF (ALLOCATED(ROUND_TARGET_BLOCK)) DEALLOCATE(ROUND_TARGET_BLOCK)
      IF (ALLOCATED(ROUND_TARGET_POSITION)) DEALLOCATE(ROUND_TARGET_POSITION)
      IF (ALLOCATED(ROUND_TARGET_OVERLAP)) DEALLOCATE(ROUND_TARGET_OVERLAP)
      IF (ALLOCATED(ROUND_TARGET_OLD_ENERGY)) DEALLOCATE(ROUND_TARGET_OLD_ENERGY)
      IF (ALLOCATED(ROUND_TARGET_NEW_ENERGY)) DEALLOCATE(ROUND_TARGET_NEW_ENERGY)
      ROUND_STATE_ACTIVE = .FALSE.
      END SUBROUTINE RELEASE_ROUND_STORAGE

      SUBROUTINE END_ORBOPT_ROUND
      CALL RELEASE_ROUND_STORAGE()
      IF (ALLOCATED(ROUND_TARGET_ACCEPTED))                         &
         DEALLOCATE(ROUND_TARGET_ACCEPTED)
      END SUBROUTINE END_ORBOPT_ROUND

      SUBROUTINE REWRITE_ROUND_MIX
!     Rewrite the .mix stream from the accepted round snapshot.
!     MATRIXmpi both diagonalises and applies CI-vector damping, so it
!     cannot be called merely to serialise a state after a rejected round.
!     The candidate .mix has already been produced by MATRIXmpi; this
!     routine replaces it with the saved accepted eigenpairs without
!     changing any in-memory state or the rollback counter.
      INTEGER :: JBLOCK, NCF, I, J, NCMINPAT, NEVECPAT
      INTEGER :: NELEC_FILE, NCFTOT_FILE, NW_FILE, NTMP1, NTMP2, NBLOCK_FILE
      INTEGER :: IATTMP, IASTMP

      IF (.NOT.ROUND_STATE_ACTIVE) RETURN
      REWIND (25)
      READ (25)
      READ (25) NELEC_FILE, NCFTOT_FILE, NW_FILE, NTMP1, NTMP2, NBLOCK_FILE
      BACKSPACE (25)
      WRITE (25) NELEC_FILE, NCFTOT, NW, NCMIN, NVECSIZ, NBLOCK

      DO JBLOCK = 1, NBLOCK
         NCF = NCFBLK(JBLOCK)
         NCMINPAT = NCMINPAST(JBLOCK)
         NEVECPAT = NEVECPAST(JBLOCK)
         IATTMP = ABS(JPGG(JBLOCK))
         IF (JPGG(JBLOCK) >= 0) THEN
            IASTMP = 1
         ELSE
            IASTMP = -1
         ENDIF
         WRITE (25) JBLOCK, NCF, NEVBLK(JBLOCK), IATTMP, IASTMP
         WRITE (25) (ICCMIN_SAVE(I + NCMINPAT), I=1,NEVBLK(JBLOCK))
         WRITE (25) EAVBLK_SAVE(JBLOCK),                              &
                    (EVAL_SAVE(I + NCMINPAT), I=1,NEVBLK(JBLOCK))
         WRITE (25) ((EVEC_SAVE(I + (J-1)*NCF + NEVECPAT),             &
                     I=1,NCF), J=1,NEVBLK(JBLOCK))
      END DO
      END SUBROUTINE REWRITE_ROUND_MIX

      REAL(DOUBLE) FUNCTION LEVEL_ENERGY(STATE, ENERGIES, AVERAGES)
      INTEGER, INTENT(IN) :: STATE
      REAL(DOUBLE), INTENT(IN) :: ENERGIES(:), AVERAGES(:)
      INTEGER :: K, OFFSET
      OFFSET = 0
      DO K = 1, NBLOCK
         IF (STATE > OFFSET .AND. STATE <= OFFSET + NEVBLK(K)) THEN
            LEVEL_ENERGY = AVERAGES(K) + ENERGIES(STATE)
            RETURN
         ENDIF
         OFFSET = OFFSET + NEVBLK(K)
      END DO
      LEVEL_ENERGY = HUGE(1.D0)
      END FUNCTION LEVEL_ENERGY

      SUBROUTINE CHECK_VECTOR_OVERLAP(MIN_OVERLAP, NONIDENTITY)
!     EVEC uses the same CSF ordering on both sides, so this coefficient
!     dot product is a cheap root-continuity diagnostic.  PF/QF change during
!     the round: without a biorthogonal orbital transformation it is not the
!     many-electron ASF overlap and must not be used as proof that a term or
!     dominant configuration is unchanged over many accepted rounds.
      REAL(DOUBLE), INTENT(OUT) :: MIN_OVERLAP
      LOGICAL, INTENT(OUT) :: NONIDENTITY
      INTEGER :: K, I, J, L, NCF, OFFSET, VOFFSET, OLD_STATE
      INTEGER :: TARGET_OLD_STATE
      INTEGER :: TARGET_ROWS_FOUND, TARGET_INDEX
      REAL(DOUBLE) :: OVERLAP
      REAL(DOUBLE), ALLOCATABLE :: OVERLAPS(:,:)
      INTEGER, ALLOCATABLE :: ASSIGNMENT(:)
      INTEGER :: IOS
      LOGICAL :: TARGET_ROW

      MIN_OVERLAP = 1.D0
      NONIDENTITY = .FALSE.
      TARGET_ROWS_FOUND = 0
      IF (ALLOCATED(ROUND_ASSIGNMENT)) DEALLOCATE(ROUND_ASSIGNMENT)
      ALLOCATE(ROUND_ASSIGNMENT(NCMIN), STAT=IOS)
      IF (IOS /= 0) ERROR STOP 'ORBOPT: vector assignment allocation failed'
      ROUND_ASSIGNMENT = 0
      IF (TARGET_STATE_COUNT > 0) THEN
         IF (.NOT.ALLOCATED(ROUND_TARGET_ACCEPTED)) THEN
            ALLOCATE(ROUND_TARGET_ACCEPTED(TARGET_STATE_COUNT), STAT=IOS)
            IF (IOS /= 0) ERROR STOP 'ORBOPT: persistent target allocation failed'
            ROUND_TARGET_ACCEPTED = TARGET_STATE_INDEX
         ELSE IF (SIZE(ROUND_TARGET_ACCEPTED) /= TARGET_STATE_COUNT) THEN
            ERROR STOP 'ORBOPT: persistent target size changed during SCF'
         ENDIF
         ALLOCATE(ROUND_TARGET_CURRENT(TARGET_STATE_COUNT),         &
                  ROUND_TARGET_BLOCK(TARGET_STATE_COUNT),           &
                  ROUND_TARGET_POSITION(TARGET_STATE_COUNT),        &
                  ROUND_TARGET_OVERLAP(TARGET_STATE_COUNT),         &
                  ROUND_TARGET_OLD_ENERGY(TARGET_STATE_COUNT),      &
                  ROUND_TARGET_NEW_ENERGY(TARGET_STATE_COUNT),      &
                  STAT=IOS)
         IF (IOS /= 0) ERROR STOP 'ORBOPT: target diagnostic allocation failed'
         ROUND_TARGET_CURRENT = 0
         ROUND_TARGET_BLOCK = 0
         ROUND_TARGET_POSITION = 0
         ROUND_TARGET_OVERLAP = 0.D0
         ROUND_TARGET_OLD_ENERGY = HUGE(1.D0)
         ROUND_TARGET_NEW_ENERGY = HUGE(1.D0)
      ENDIF
      OFFSET = 0
      VOFFSET = 0
      DO K = 1, NBLOCK
         NCF = NCFBLK(K)
         ALLOCATE(OVERLAPS(NEVBLK(K), NEVBLK(K)),                 &
                  ASSIGNMENT(NEVBLK(K)), STAT=IOS)
         IF (IOS /= 0) ERROR STOP 'ORBOPT: vector matching allocation failed'
         DO I = 1, NEVBLK(K)
            DO J = 1, NEVBLK(K)
               OVERLAPS(I,J) = ABS(DOT_PRODUCT(                     &
                  EVEC(VOFFSET + (I-1)*NCF + 1:                    &
                       VOFFSET + I*NCF),                            &
                  EVEC_SAVE(VOFFSET + (J-1)*NCF + 1:                &
                       VOFFSET + J*NCF)))
            END DO
         END DO
         CALL MAX_WEIGHT_ASSIGNMENT(OVERLAPS, ASSIGNMENT)
         DO I = 1, NEVBLK(K)
            OLD_STATE = ASSIGNMENT(I)
            IF (OLD_STATE < 1 .OR. OLD_STATE > NEVBLK(K)) CYCLE
            OVERLAP = OVERLAPS(I, OLD_STATE)
            ROUND_ASSIGNMENT(OFFSET + I) = OFFSET + OLD_STATE
            ! A block can contain auxiliary roots that are intentionally
            ! allowed to rearrange while the requested physical states stay
            ! well tracked.  When a target list is supplied, apply the
            ! overlap gate only to assignment columns representing those
            ! old physical roots; still retain the complete assignment for
            ! diagnostics and for mapping target energies below.
            ! TARGET_STATE_INDEX contains old, physical root indices.  The
            ! Hungarian assignment maps a candidate row (I) to its old root
            ! column (OLD_STATE), so the target gate must follow the column.
            ! Testing OFFSET+I here would inspect an unrelated root whenever
            ! two roots exchange row positions.
            TARGET_ROW = TARGET_STATE_COUNT == 0
            TARGET_INDEX = 0
            IF (.NOT.TARGET_ROW) THEN
               DO L = 1, TARGET_STATE_COUNT
                  TARGET_OLD_STATE = ROUND_TARGET_ACCEPTED(L)
                  IF (TARGET_OLD_STATE == OFFSET + OLD_STATE) THEN
                     TARGET_ROW = .TRUE.
                     TARGET_INDEX = L
                     EXIT
                  ENDIF
               END DO
            ENDIF
            IF (TARGET_ROW) THEN
               MIN_OVERLAP = MIN(MIN_OVERLAP, OVERLAP)
               IF (TARGET_STATE_COUNT > 0) THEN
                  TARGET_ROWS_FOUND = TARGET_ROWS_FOUND + 1
                  ROUND_TARGET_CURRENT(TARGET_INDEX) = OFFSET + I
                  ROUND_TARGET_BLOCK(TARGET_INDEX) = K
                  ROUND_TARGET_POSITION(TARGET_INDEX) = I
                  ROUND_TARGET_OVERLAP(TARGET_INDEX) = OVERLAP
                  ROUND_TARGET_OLD_ENERGY(TARGET_INDEX) =           &
                       LEVEL_ENERGY(OFFSET + OLD_STATE, EVAL_SAVE,  &
                                    EAVBLK_SAVE)
                  ROUND_TARGET_NEW_ENERGY(TARGET_INDEX) =           &
                       LEVEL_ENERGY(OFFSET + I, EVAL, EAVBLK)
               ENDIF
            ENDIF
            IF (OLD_STATE /= I) NONIDENTITY = .TRUE.
         END DO
         DEALLOCATE(OVERLAPS, ASSIGNMENT)
         OFFSET = OFFSET + NEVBLK(K)
         VOFFSET = VOFFSET + NEVBLK(K)*NCF
      END DO
      IF (TARGET_STATE_COUNT > 0 .AND. TARGET_ROWS_FOUND < &
          TARGET_STATE_COUNT) MIN_OVERLAP = 0.D0
      END SUBROUTINE CHECK_VECTOR_OVERLAP

      SUBROUTINE CHECK_TARGET_ENERGY_ORDER(ORDER_CHANGED)
      LOGICAL, INTENT(OUT) :: ORDER_CHANGED
      INTEGER, ALLOCATABLE :: OLD_ORDER(:), NEW_ORDER(:)
      REAL(DOUBLE), ALLOCATABLE :: OLD_ENERGY(:), NEW_ENERGY(:)
      INTEGER :: I, J, CURRENT_STATE, IOS

      ORDER_CHANGED = .FALSE.
      IF (TARGET_STATE_COUNT < 2) RETURN
      IF (.NOT.ALLOCATED(ROUND_ASSIGNMENT)) RETURN
      ALLOCATE(OLD_ORDER(TARGET_STATE_COUNT), NEW_ORDER(TARGET_STATE_COUNT), &
               OLD_ENERGY(TARGET_STATE_COUNT), NEW_ENERGY(TARGET_STATE_COUNT), &
               STAT=IOS)
      IF (IOS /= 0) ERROR STOP 'ORBOPT: target-order allocation failed'
      DO I = 1, TARGET_STATE_COUNT
         OLD_ORDER(I) = TARGET_STATE_INDEX(I)
         OLD_ENERGY(I) = ROUND_TARGET_OLD_ENERGY(I)
         CURRENT_STATE = 0
         DO J = 1, NCMIN
            IF (ROUND_ASSIGNMENT(J) == ROUND_TARGET_ACCEPTED(I)) THEN
               CURRENT_STATE = J
               EXIT
            ENDIF
         END DO
         IF (CURRENT_STATE == 0) THEN
            NEW_ENERGY(I) = HUGE(1.D0)
         ELSE
            NEW_ENERGY(I) = ROUND_TARGET_NEW_ENERGY(I)
         ENDIF
         NEW_ORDER(I) = TARGET_STATE_INDEX(I)
      END DO
      CALL SORT_STATE_ORDER(OLD_ENERGY, OLD_ORDER)
      CALL SORT_STATE_ORDER(NEW_ENERGY, NEW_ORDER)
      DO I = 1, TARGET_STATE_COUNT
         IF (OLD_ORDER(I) /= NEW_ORDER(I)) THEN
            ORDER_CHANGED = .TRUE.
            EXIT
         ENDIF
      END DO
      DEALLOCATE(OLD_ORDER, NEW_ORDER, OLD_ENERGY, NEW_ENERGY)
      END SUBROUTINE CHECK_TARGET_ENERGY_ORDER

      SUBROUTINE SORT_STATE_ORDER(ENERGIES, ORDER)
      REAL(DOUBLE), INTENT(IN) :: ENERGIES(:)
      INTEGER, INTENT(INOUT) :: ORDER(:)
      INTEGER :: I, J, TMP_STATE
      REAL(DOUBLE) :: TMP_ENERGY
      REAL(DOUBLE), ALLOCATABLE :: SORTED_ENERGY(:)

      ALLOCATE(SORTED_ENERGY(SIZE(ENERGIES)))
      SORTED_ENERGY = ENERGIES
      DO I = 1, SIZE(ORDER) - 1
         DO J = I + 1, SIZE(ORDER)
            IF (SORTED_ENERGY(J) < SORTED_ENERGY(I)) THEN
               TMP_ENERGY = SORTED_ENERGY(I)
               SORTED_ENERGY(I) = SORTED_ENERGY(J)
               SORTED_ENERGY(J) = TMP_ENERGY
               TMP_STATE = ORDER(I)
               ORDER(I) = ORDER(J)
               ORDER(J) = TMP_STATE
            ENDIF
         END DO
      END DO
      DEALLOCATE(SORTED_ENERGY)
      END SUBROUTINE SORT_STATE_ORDER

      SUBROUTINE MAX_WEIGHT_ASSIGNMENT(WEIGHTS, ASSIGNMENT)
!     Kuhn-Munkres assignment for a square overlap matrix.  ASSIGNMENT(I)
!     is the old-state column assigned to current-state row I.
      REAL(DOUBLE), INTENT(IN) :: WEIGHTS(:,:)
      INTEGER, INTENT(OUT) :: ASSIGNMENT(:)
      INTEGER :: N, I, J, J0, J1, I0, IOS
      REAL(DOUBLE) :: DELTA, CUR, BIG
      REAL(DOUBLE), ALLOCATABLE :: U(:), V(:), MINV(:)
      INTEGER, ALLOCATABLE :: P(:), WAY(:)
      LOGICAL, ALLOCATABLE :: USED(:)

      N = SIZE(ASSIGNMENT)
      IF (SIZE(WEIGHTS, 1) /= N .OR. SIZE(WEIGHTS, 2) /= N) THEN
         ERROR STOP 'ORBOPT: non-square assignment matrix'
      ENDIF
      BIG = HUGE(1.D0)
      ALLOCATE(U(0:N), V(0:N), MINV(0:N), P(0:N), WAY(0:N),       &
               USED(0:N), STAT=IOS)
      IF (IOS /= 0) ERROR STOP 'ORBOPT: assignment allocation failed'
      U = 0.D0
      V = 0.D0
      P = 0
      WAY = 0
      DO I = 1, N
         P(0) = I
         J0 = 0
         MINV = BIG
         USED = .FALSE.
         DO
            USED(J0) = .TRUE.
            I0 = P(J0)
            DELTA = BIG
            J1 = 0
            DO J = 1, N
               IF (USED(J)) CYCLE
               CUR = -WEIGHTS(I0,J) - U(I0) - V(J)
               IF (CUR < MINV(J)) THEN
                  MINV(J) = CUR
                  WAY(J) = J0
               ENDIF
               IF (MINV(J) < DELTA) THEN
                  DELTA = MINV(J)
                  J1 = J
               ENDIF
            END DO
            DO J = 0, N
               IF (USED(J)) THEN
                  U(P(J)) = U(P(J)) + DELTA
                  V(J) = V(J) - DELTA
               ELSE
                  MINV(J) = MINV(J) - DELTA
               ENDIF
            END DO
            J0 = J1
            IF (P(J0) == 0) EXIT
         END DO
         DO
            J1 = WAY(J0)
            P(J0) = P(J1)
            J0 = J1
            IF (J0 == 0) EXIT
         END DO
      END DO
      ASSIGNMENT = 0
      DO J = 1, N
         IF (P(J) >= 1 .AND. P(J) <= N) ASSIGNMENT(P(J)) = J
      END DO
      DEALLOCATE(U, V, MINV, P, WAY, USED)
      END SUBROUTINE MAX_WEIGHT_ASSIGNMENT

      END MODULE ORBOPT_ROUND_STATE_C
