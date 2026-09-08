!***********************************************************************
!  Diagnostic-only quality metrics for a candidate radial orbital.
!  This module does not accept, reject, damp, or otherwise alter updates.
!***********************************************************************
      MODULE ORBOPT_METRICS_C
      USE vast_kind_param, ONLY: DOUBLE
      USE parameter_def, ONLY: NNNP
      USE grid_C, ONLY: r, rp
      USE int_C, ONLY: p, q, mtp0
      USE tatb_C, ONLY: ta, mtp
      USE wave_C, ONLY: mf, pf, qf
      USE coun_C, ONLY: COUNT_CONTEXT
      USE count_I
      USE quad_I
      IMPLICIT NONE

      CONTAINS

      SUBROUTINE CALCULATE_ORBITAL_METRICS(J, CANDIDATE_NORM,       &
            OLD_NORM, OVERLAP, RADIUS_OLD, RADIUS_CANDIDATE,       &
            NODES_OLD, NODES_CANDIDATE)
      INTEGER, INTENT(IN) :: J
      INTEGER, INTENT(OUT) :: NODES_OLD, NODES_CANDIDATE
      REAL(DOUBLE), INTENT(OUT) :: CANDIDATE_NORM, OLD_NORM
      REAL(DOUBLE), INTENT(OUT) :: OVERLAP, RADIUS_OLD
      REAL(DOUBLE), INTENT(OUT) :: RADIUS_CANDIDATE
      REAL(DOUBLE) :: SGN
      INTEGER :: LIMIT

!     Candidate norm and mean radius, using the same quadrature
!     convention as SOLVE and RINT.
      MTP = MTP0
      TA(1) = 0.D0
      TA(2:MTP) = (P(2:MTP)**2 + Q(2:MTP)**2)*RP(2:MTP)
      CALL QUAD(CANDIDATE_NORM)
      TA(1) = 0.D0
      TA(2:MTP) = R(2:MTP)*(P(2:MTP)**2 + Q(2:MTP)**2)*RP(2:MTP)
      CALL QUAD(RADIUS_CANDIDATE)

!     Stored-orbital norm and mean radius.
      MTP = MF(J)
      TA(1) = 0.D0
      TA(2:MTP) = (PF(2:MTP,J)**2 + QF(2:MTP,J)**2)*RP(2:MTP)
      CALL QUAD(OLD_NORM)
      TA(1) = 0.D0
      TA(2:MTP) = R(2:MTP)*(PF(2:MTP,J)**2 + QF(2:MTP,J)**2)      &
                              *RP(2:MTP)
      CALL QUAD(RADIUS_OLD)

!     Signed overlap between the normalized candidate and old orbital.
      LIMIT = MIN(MTP0, MF(J))
      MTP = LIMIT
      TA(1) = 0.D0
      TA(2:MTP) = (P(2:MTP)*PF(2:MTP,J) +                       &
                    Q(2:MTP)*QF(2:MTP,J))*RP(2:MTP)
      CALL QUAD(OVERLAP)

      COUNT_CONTEXT = J
      CALL COUNT(P(:NNNP), MTP0, NODES_CANDIDATE, SGN)
      CALL COUNT(PF(:NNNP,J), MF(J), NODES_OLD, SGN)
      END SUBROUTINE CALCULATE_ORBITAL_METRICS

      SUBROUTINE CHECK_ORBITAL_QUALITY(OVERLAP, RADIUS_OLD,         &
            RADIUS_CANDIDATE, NODES_OLD, NODES_CANDIDATE,         &
            EXPECTED_NODES, MIN_OVERLAP, MAX_RADIUS_FACTOR,        &
            REJECT_NODES, NODE_PROGRESS, REJECT, DETAIL)
      REAL(DOUBLE), INTENT(IN) :: OVERLAP, RADIUS_OLD
      REAL(DOUBLE), INTENT(IN) :: RADIUS_CANDIDATE, MIN_OVERLAP
      REAL(DOUBLE), INTENT(IN) :: MAX_RADIUS_FACTOR
      INTEGER, INTENT(IN) :: NODES_OLD, NODES_CANDIDATE
      INTEGER, INTENT(IN) :: EXPECTED_NODES
      LOGICAL, INTENT(IN) :: REJECT_NODES
      LOGICAL, INTENT(IN) :: NODE_PROGRESS
      LOGICAL, INTENT(OUT) :: REJECT
      CHARACTER(LEN=*), INTENT(OUT) :: DETAIL
      REAL(DOUBLE) :: RADIUS_FACTOR

      REJECT = .FALSE.
      DETAIL = ''
      IF (RADIUS_OLD > 0.D0 .AND. RADIUS_CANDIDATE > 0.D0) THEN
         RADIUS_FACTOR = MAX(RADIUS_OLD/RADIUS_CANDIDATE,          &
                             RADIUS_CANDIDATE/RADIUS_OLD)
      ELSE
         RADIUS_FACTOR = HUGE(1.D0)
      ENDIF

      IF (ABS(OVERLAP) < MIN_OVERLAP) THEN
         REJECT = .TRUE.
         DETAIL = 'overlap'
      ENDIF
      IF (RADIUS_FACTOR > MAX_RADIUS_FACTOR) THEN
         REJECT = .TRUE.
         IF (LEN_TRIM(DETAIL) > 0) DETAIL = TRIM(DETAIL)//'+'
         DETAIL = TRIM(DETAIL)//'radius'
      ENDIF
!     A correction from an imperfect initial estimate may take more than
!     one damped update.  In progress mode accept only a non-worsening
!     distance from the Dirac orbital's required node count.  The legacy
!     mode retains the exact expected-node check.
      IF (REJECT_NODES) THEN
         IF (NODE_PROGRESS) THEN
            IF (ABS(NODES_CANDIDATE - EXPECTED_NODES) >             &
                ABS(NODES_OLD - EXPECTED_NODES)) THEN
               REJECT = .TRUE.
               IF (LEN_TRIM(DETAIL) > 0) DETAIL = TRIM(DETAIL)//'+'
               DETAIL = TRIM(DETAIL)//'nodes_progress'
            ENDIF
         ELSE IF (NODES_CANDIDATE /= EXPECTED_NODES) THEN
            REJECT = .TRUE.
            IF (LEN_TRIM(DETAIL) > 0) DETAIL = TRIM(DETAIL)//'+'
            DETAIL = TRIM(DETAIL)//'nodes_expected'
         ENDIF
      ENDIF
      END SUBROUTINE CHECK_ORBITAL_QUALITY

      END MODULE ORBOPT_METRICS_C
