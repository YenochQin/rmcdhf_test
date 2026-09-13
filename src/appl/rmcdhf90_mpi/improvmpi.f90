!***********************************************************************
      SUBROUTINE IMPROVmpi (EOL, J, LSORT, DAMPMX)
!   The difference from the serial version is that it calls MPI        *
!   version subroutines (setlagmpi, cofpotmpi, matrixmpi, newcompi).   *
!                                                                      *
!   Improve the orbital J.                                             *
!                                                                      *
!   Call(s) to: [RSCF92]: DACON, DAMPCK, DAMPOR, LAGCON, matrixmpi,    *
!                         newcompi, ORTHOR, ROTATE, SETCOF, setlagmpi, *
!                         SOLVE, XPOT, YPOT.                           *
!               [LIB92]: ORTHSC, QUAD.                                 *
!                                                                      *
!   Written by Farid A Parpia, at Oxford    Last update: 22 Dec 1992   *
!   Modified by Xinghong He                 Last update: 05 Aug 1988   *
!   Modified for ifort -i8 by A. Kramida (AK) Last update 22 Mar 2016  *
!                                                                      *
!***********************************************************************
!...Translated by Pacific-Sierra Research 77to90  4.3E  14:04:58   1/ 3/07
!...Modified by Charlotte Froese Fischer
!                     Gediminas Gaigalas  10/05/17
!-----------------------------------------------
!   M o d u l e s
!-----------------------------------------------
      USE vast_kind_param, ONLY:  DOUBLE
      USE memory_man
      USE CORRE_C
      USE damp_C
      USE def_C
      USE grid_C
      USE int_C
      USE mpi_C
      USE node_C, ONLY: NNODEP
      USE orb_C
      USE orthct_C
      USE scf_C
      USE tatb_C
      USE wave_C
      USE ORBOPT_CONTROL_C, ONLY: TRACE_ORBOPT,                     &
            ENABLE_ORBITAL_GUARD, MIN_ORBITAL_OVERLAP,             &
            MAX_RADIUS_RATIO, REJECT_NODE_CHANGE,                  &
            RECORD_ORBITAL_REJECTION, CLEAR_ORBITAL_REJECTIONS,    &
            STRICT_METHOD3, GUARD_AFTER_DAMPING, NODE_PROGRESS_GUARD
      USE ORBOPT_METRICS_C, ONLY: CALCULATE_ORBITAL_METRICS
      USE ORBOPT_METRICS_C, ONLY: CHECK_ORBITAL_QUALITY
      USE ORBOPT_TRACE_C, ONLY: TRACE_ORBITAL_UPDATE,               &
                                TRACE_ORBITAL_METRICS
!-----------------------------------------------
!   I n t e r f a c e   B l o c k s
!-----------------------------------------------
      USE cofpotmpi_I
      USE defcor_I
      USE solve_I
      USE orthsc_I
!GG      USE matrixmpi_I
!GG      USE newcompi_I
      USE setlagmpi_I
      USE quad_I
      USE consis_I
      USE dampck_I
      USE dampor_I
      USE orthy_I
      IMPLICIT NONE
!-----------------------------------------------
!   D u m m y   A r g u m e n t s
!-----------------------------------------------
      INTEGER  :: J
      REAL(DOUBLE), INTENT(INOUT) :: DAMPMX
      LOGICAL  :: EOL, LSORT
!-----------------------------------------------
!   L o c a l   P a r a m e t e r s
!-----------------------------------------------
      REAL(DOUBLE), PARAMETER :: P2 = 2.0D-01
      REAL(DOUBLE), PARAMETER :: P005 = 5.0D-03
      REAL(DOUBLE), PARAMETER :: P0001 = 1.0D-04
!-----------------------------------------------
!   L o c a l   V a r i a b l e s
!-----------------------------------------------
      INTEGER :: IPR, NPTS, INV, JP, NNP, I, NWWW
      INTEGER :: I_MPI, ndcof_max, ntot, i_last, iproc, ndcip, jproc
      INTEGER :: ifound, ind_buf, K
      INTEGER :: NODES_OLD, NODES_CANDIDATE, MF_OLD
      INTEGER :: MTP0_OLD
      INTEGER :: REJECT_COUNT, INV_OLD, NSIC_OLD, METHOD_OLD
      REAL(DOUBLE) :: ED1, GAMAJ, ED2, EOLD, WTAEV, DNORM, DNFAC
      REAL(DOUBLE) :: P_SWAP, Q_SWAP
      REAL(DOUBLE) :: DEL1, DEL2, ODAMPJ
      REAL(DOUBLE) :: CANDIDATE_NORM, OLD_NORM, ORBITAL_OVERLAP
      REAL(DOUBLE) :: RADIUS_OLD, RADIUS_CANDIDATE
      REAL(DOUBLE) :: PZ_OLD, SCNSTY_OLD, ODAMP_OLD, ENERGY_CANDIDATE
      LOGICAL :: FAIL, FIRST, REJECT_CANDIDATE, REJECT_LIMIT
      LOGICAL :: FALLBACK
      CHARACTER(LEN=128) :: REJECT_DETAIL, QUALITY_DETAIL
      REAL(DOUBLE), DIMENSION(:), POINTER :: da_buffer
      INTEGER, DIMENSION(:), POINTER :: nda_buffer,ndcof_buffer,ndcof_disp
!-----------------------------------------------
!
!   C Froese Fischer's IPR and ED1 parameter
!
      DATA IPR/ 0/
      DATA ED1/ 0.D0/
      DATA FIRST/ .FALSE./
!
!
!-----------------------------------------------------------------------
!AK Handling the -i8 option of ifort and -fdefault-integer-8 option of gfortran
!      ISIZE = sizeof(NCF)
      I_MPI = MPI_INTEGER
!      if (ISIZE.EQ.8) I_MPI = MPI_INTEGER8
!
      GAMAJ = GAMA(J)
      FALLBACK = .FALSE.
      EOLD = E(J)
      MF_OLD = MF(J)
      MTP0_OLD = MTP0
      PZ_OLD = PZ(J)
      SCNSTY_OLD = SCNSTY(J)
      ODAMP_OLD = ODAMP(J)
      NSIC_OLD = NSIC
      METHOD_OLD = METHOD(J)
      ODAMPJ = 0.D0
!
!   C Froese Fischer's parameters IPR, ED1, ED2 are set and
!   used in this routine and in DAMPCK
!
    1 CONTINUE
      ED2 = E(J)
      ED1 = PED(J)
!
!   Set up the exchange potential and arrays XU, XV as appropriate
!
!   Set coefficients for YPOT, XPOT, DACON
!   Compute direct potential, exchange potential
!   Add in Lagrange-multiplier contribution
!   Add in derivative-terms contribution
!
      NPTS = N
      CALL COFPOTmpi (EOL, J, NPTS)
!
!   Calculate deferred corrections
!
      CALL DEFCOR (J)
!
!   Solve the Dirac equation
!
!AK     NDCOF, NDA, and DA cannot be reduced by finding the max of NDCOF
!          and summing up DA from all nodes. The correct replacement is below
!cjb MPI_ALLREDUCE NDCOF
!      call MPI_ALLREDUCE(ndcof,ndcof_buffer,1,
!     :          I_MPI,MPI_MAX,MPI_COMM_WORLD,ierror)
!      if (ndcof_buffer .gt. ndcof) then
!        print *, 'improvmpi: ndcof, ndcof_buffer, myid=',
!     &                     ndcof, ndcof_buffer, myid
!        write (*,'(A35,4I10)') 'improv11: myid,NDCOF,ndcbfr=',
!     &    myid,NDCOF,ndcof_buffer
!        do indcof = ndcof+1, ndcof_buffer
!           da(indcof) = 0.0
!           nda(indcof) = 0
!        enddo
!        ndcof = ndcof_buffer
!      endif
      INV = 0
      INV_OLD = INV
!cjb MPI_ALLREDUCE DA
!      if (ndcof.gt.0) then
!         call alloc(pda_buffer, ndcof, 8)
!         call alloc(pnda_buffer, ndcof, ISIZE)
!         call MPI_ALLREDUCE(da,da_buffer,ndcof,
!     :          MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,ierror)
!         da(1:ndcof) = da_buffer(1:ndcof)
!      nda(1:ndcof) = nda_buffer(1:ndcof)
!         call dalloc(pda_buffer)
!         call dalloc(pnda_buffer)
!      ENDIF
!AK      Consolidate NDA and DA from all nodes
      if (nprocs.gt.1) then
         call alloc(ndcof_buffer,nprocs,'ndcof_buffer','IMPROVmpi')
         call MPI_GATHER(ndcof, 1, I_MPI, ndcof_buffer,            &
              1, I_MPI, 0, MPI_COMM_WORLD, ierr)
         CALL MPI_Bcast (ndcof_buffer, nprocs, I_MPI, 0,           &
                               MPI_COMM_WORLD, ierr)
         ndcof_max = 0
         do i = 1, nprocs
            if (ndcof_buffer(i).gt.ndcof_max) ndcof_max=ndcof_buffer(i)
         ENDDO
         if (ndcof_max.gt.0) then
            ! Each rank can produce a different number of coefficients.
            ! Gather only the initialized part of each local NDA/DA array;
            ! using ndcof_max as the send count reads past short local lists
            ! and can feed uninitialized labels into the merge below.
            call alloc(ndcof_disp,nprocs,'ndcof_disp','IMPROVmpi')
            ndcof_disp(1) = 0
            do i = 2, nprocs
               ndcof_disp(i) = ndcof_disp(i-1) + ndcof_buffer(i-1)
            enddo
            ntot = ndcof_disp(nprocs) + ndcof_buffer(nprocs)
            call alloc(nda_buffer,ntot,'nda_buffer','IMPROVmpi')
            call MPI_Gatherv(nda, ndcof, I_MPI, nda_buffer,        &
                 ndcof_buffer, ndcof_disp, I_MPI, 0,              &
                 MPI_COMM_WORLD, ierr)
            CALL MPI_Bcast (nda_buffer, ntot, I_MPI, 0,            &
                               MPI_COMM_WORLD, ierr)
            call alloc(da_buffer, ntot, 'da_buffer','IMPROVmpi')
            call MPI_Gatherv(da, ndcof, MPI_DOUBLE_PRECISION,     &
              da_buffer, ndcof_buffer, ndcof_disp,                &
              MPI_DOUBLE_PRECISION, 0, MPI_COMM_WORLD, ierr)
            CALL MPI_Bcast (da_buffer, ntot, MPI_DOUBLE_PRECISION, &
                               0, MPI_COMM_WORLD, ierr)
            i_last = 0
            do iproc = 1, nprocs
               ndcip = ndcof_buffer(iproc)
               do jproc = 1, ndcip
                  ifound = 0
                  ! MPI_Gatherv packs each rank at its actual displacement;
                  ! ndcof_max is only the largest local count and is not a
                  ! valid stride for the gathered buffer.
                  ind_buf = ndcof_disp(iproc) + jproc
                  do k = 1, i_last
                     if (nda_buffer(ind_buf) .eq. NDA(k)) THEN
                        DA(k) = DA(k) + da_buffer(ind_buf)
                        ifound = k
                        exit
                     endif
                  enddo
                  if (ifound.eq.0) then
                     i_last = i_last + 1
                     do while (i_last .GT. NDDIM)
                        IF (NDDIM .GT. 0) THEN
                           NDDIM = 2*NDDIM
!GG                           CALL alcsca (PNTNDA, PNTRDA, NDDIM, 2)
                           CALL RALLOC(NDA,NDDIM,'NDA','IMPROVmpi')
                        ELSE
                          NDDIM = 64
!GG                           CALL alcsca (PNTNDA, PNTRDA, NDDIM, 1)
                           CALL ALLOC(NDA,NDDIM,'NDA','IMPROVmpi')
                        ENDIF
                     ENDdo
                     NDA(i_last) = nda_buffer(ind_buf)
                     DA(i_last) = da_buffer(ind_buf)
                  endif
               enddo
            enddo
            ! NDCOF is the number of unique coefficients actually merged.
            ! The union of rank-local NDA lists can exceed the longest local
            ! list.  Using ndcof_max truncates that union, so DACON ignores
            ! valid coefficients stored above the local maximum.
            NDCOF = i_last
            call dalloc(nda_buffer,'nda_buffer','IMPROVmpi')
            call dalloc(da_buffer,'da_buffer','IMPROVMPI')
            call dalloc(ndcof_disp,'ndcof_disp','IMPROVmpi')
         endif
         call dalloc(ndcof_buffer,'ndcof_buffer','IMPROVmpi')
      endif

      CALL SOLVE (J, FAIL, INV, JP, NNP)
      CALL TRACE_ORBITAL_UPDATE('solve_result', 0, J, EOLD, E(J),   &
                                0.D0, 0.D0, INV, JP, NNP, FALLBACK,&
                                FAIL)
!
!   Upon failure issue message; take corrective action if possible
!
      IF (FAIL) THEN
         IF (MYID == 0) WRITE (*, 300) NP(J), NH(J), METHOD(J)
         IF (STRICT_METHOD3) THEN
            IF (MYID == 0) WRITE (*,'(A,I0,A,A)')                  &
               'ORBOPT strict METHOD=3 failed for ', NP(J), NH(J), &
               '; fallback disabled'
            ERROR STOP 'ORBOPT strict METHOD=3 solve failure'
         ENDIF
         IF (METHOD(J) /= 2) THEN
            METHOD(J) = 2
            FALLBACK = .TRUE.
!XHH orthsc does not have any argument
!    Orbital J [PF() and QF()]is not updated, why redo orthogonalization
            CALL ORTHSC
!CFF        ... avoid rediagonalization
!            IF (EOL) THEN
!               CALL MATRIXMPI
!               CALL NEWCOMPI (WTAEV)
!            ENDIF
            CALL SETLAGmpi (EOL)
            GO TO 1
         ELSE
            IF (MYID == 0) WRITE (*, 301)
            !CALL TIMER (0)
            ERROR STOP
         ENDIF
      ENDIF
!
!   Compute norm of radial function
!
      TA(1) = 0.D0
      TA(2:MTP0) = (P(2:MTP0)**2+Q(2:MTP0)**2)*RP(2:MTP0)
      MTP = MTP0

      CALL QUAD (DNORM)

!   Determine self-consistency [multiplied by SQRT(UCF(J))]

      CALL CONSIS (J)
      CALL TRACE_ORBITAL_UPDATE('candidate', 0, J, EOLD, E(J),      &
                                DNORM, 0.D0, INV, JP, NNP, FALLBACK,&
                                .FALSE.)
!
!   Normalize
!
      DNFAC = 1.D0/DSQRT(DNORM)
      P0 = P0*DNFAC
      P(:MTP0) = P(:MTP0)*DNFAC
      Q(:MTP0) = Q(:MTP0)*DNFAC

!   Record candidate quality without changing the acceptance path.
      IF (TRACE_ORBOPT .OR. ENABLE_ORBITAL_GUARD) THEN
         CALL CALCULATE_ORBITAL_METRICS(J, CANDIDATE_NORM, OLD_NORM,&
              ORBITAL_OVERLAP, RADIUS_OLD, RADIUS_CANDIDATE,       &
              NODES_OLD, NODES_CANDIDATE)
         IF (TRACE_ORBOPT) CALL TRACE_ORBITAL_METRICS(0, J,        &
              CANDIDATE_NORM, OLD_NORM, ORBITAL_OVERLAP,           &
              RADIUS_OLD, RADIUS_CANDIDATE, NODES_OLD,             &
              NODES_CANDIDATE, MF(J), MTP0, E(J)-EOLD)
      ENDIF
!
!   Check if different method should be used or if improvement
!   count should be reduced
!
      DEL1 = DABS(1.D0 - ED2/E(J))
      IF (METHOD(J) == 1) THEN
         DEL2 = DMAX1(DABS(1.D0 - DSQRT(DNORM)),DABS(DNFAC - 1.D0))
         IF (DEL1<P005 .AND. DEL2>P2) THEN
            METHOD(J) = 2
            GO TO 1
         ENDIF
      ELSE
         IF (DEL1<P0001 .AND. NSIC>1) NSIC = NSIC - 1
      ENDIF

!   Optionally reject a pathological raw candidate before it can alter
!   PF/QF through damping or orthogonalization. The historical path is
!   unchanged while GRASP_ORBITAL_GUARD is disabled.
      IF (ENABLE_ORBITAL_GUARD) THEN
         CALL CHECK_ORBITAL_QUALITY(ORBITAL_OVERLAP, RADIUS_OLD,    &
              RADIUS_CANDIDATE, NODES_OLD, NODES_CANDIDATE,       &
              NNODEP(J), MIN_ORBITAL_OVERLAP, MAX_RADIUS_RATIO,    &
              REJECT_NODE_CHANGE .AND. .NOT. NODE_PROGRESS_GUARD,   &
              NODE_PROGRESS_GUARD,                                  &
              REJECT_CANDIDATE, QUALITY_DETAIL)
!        Progress mode validates every damped update.  This prevents a
!        raw candidate that happens to equal NNODEP from being followed by
!        a damped candidate that moves away from it.
         IF (GUARD_AFTER_DAMPING .AND. NODE_PROGRESS_GUARD)          &
            REJECT_CANDIDATE = .TRUE.
         IF (REJECT_CANDIDATE) THEN
            IF (GUARD_AFTER_DAMPING) THEN
!              Try the normal damping operation before rejecting the raw
!              candidate.  DAMPOR swaps P/PF, so a failed post-damp check can
!              be rolled back by swapping them back and restoring scalars.
               IF (SCNSTY(J) > ACCY) THEN
                  CALL DAMPCK (IPR, J, ED1, ED2)
                  ODAMPJ = DABS(ODAMP(J))
               ELSE
                  ODAMPJ = 0.D0
               ENDIF
               CALL DAMPOR (J, INV, ODAMPJ)
               CALL CALCULATE_ORBITAL_METRICS(J, CANDIDATE_NORM,  &
                    OLD_NORM, ORBITAL_OVERLAP, RADIUS_OLD,        &
                    RADIUS_CANDIDATE, NODES_OLD, NODES_CANDIDATE)
               CALL CHECK_ORBITAL_QUALITY(ORBITAL_OVERLAP,        &
                    RADIUS_CANDIDATE, RADIUS_OLD, NODES_CANDIDATE, &
                    NODES_OLD, NNODEP(J), MIN_ORBITAL_OVERLAP,     &
                    MAX_RADIUS_RATIO, REJECT_NODE_CHANGE,         &
                    NODE_PROGRESS_GUARD, REJECT_CANDIDATE,        &
                    QUALITY_DETAIL)
               IF (.NOT. REJECT_CANDIDATE) THEN
                  CALL CLEAR_ORBITAL_REJECTIONS(J)
                  GOTO 900
               ENDIF
!              Restore the pre-damping workspace and scalar state.
               DO I = 1, MAX(MTP0, MF(J))
                  P_SWAP = P(I)
                  P(I) = PF(I,J)
                  PF(I,J) = P_SWAP
                  Q_SWAP = Q(I)
                  Q(I) = QF(I,J)
                  QF(I,J) = Q_SWAP
               END DO
               MF(J) = MF_OLD
               MTP0 = MTP0_OLD
               PZ(J) = PZ_OLD
               SCNSTY(J) = SCNSTY_OLD
               ODAMP(J) = ODAMP_OLD
               NSIC = NSIC_OLD
               METHOD(J) = METHOD_OLD
               INV = INV_OLD
            ENDIF
            ENERGY_CANDIDATE = E(J)
            CALL RECORD_ORBITAL_REJECTION(J, REJECT_COUNT,         &
                                           REJECT_LIMIT)
            WRITE (REJECT_DETAIL,'(A,A,I0)') TRIM(QUALITY_DETAIL), &
                                             ';count=', REJECT_COUNT
            E(J) = EOLD
            MF(J) = MF_OLD
            PZ(J) = PZ_OLD
            SCNSTY(J) = MAX(SCNSTY_OLD, 10.D0*ACCY)
            ODAMP(J) = -MIN(0.9D0, MAX(ABS(ODAMP(J)), 0.5D0) +    &
                                      0.2D0*DBLE(REJECT_COUNT-1))
            CALL TRACE_ORBITAL_UPDATE('rejected', 0, J, EOLD,     &
                 ENERGY_CANDIDATE, DNORM, ABS(ODAMP(J)), INV, JP, &
                 NNP, FALLBACK, .FALSE., REJECT_DETAIL)
            IF (MYID == 0) WRITE (*,'(A,1X,I0,4A,I0)')             &
                 'ORBOPT rejected orbital', NP(J), NH(J), ': ',   &
                 TRIM(QUALITY_DETAIL), '; count=', REJECT_COUNT
            IF (REJECT_LIMIT) THEN
               IF (MYID == 0) WRITE (*,'(A,1X,I0,A,A)')           &
                    'ORBOPT rejection limit exceeded for', NP(J), &
                    NH(J), '; stopping before false convergence'
               ERROR STOP 'ORBOPT orbital rejection limit exceeded'
            ENDIF
            RETURN
         ENDIF
      ENDIF
!
!   Damp the orbital --- if not converged
!
      IF (SCNSTY(J) > ACCY) THEN
         CALL DAMPCK (IPR, J, ED1, ED2)
         ODAMPJ = DABS(ODAMP(J))
      ELSE
         ODAMPJ = 0.D0                           ! take the whole new orbital
      ENDIF
      CALL DAMPOR (J, INV, ODAMPJ)
  900 CONTINUE
      CALL CLEAR_ORBITAL_REJECTIONS(J)
      IF (TRACE_ORBOPT) THEN
!        DAMPOR leaves the preceding accepted orbital in P/Q and the
!        newly accepted (possibly damped) orbital in PF/QF.
         CALL CALCULATE_ORBITAL_METRICS(J, CANDIDATE_NORM, OLD_NORM,&
              ORBITAL_OVERLAP, RADIUS_OLD, RADIUS_CANDIDATE,       &
              NODES_OLD, NODES_CANDIDATE)
         CALL TRACE_ORBITAL_METRICS(0, J, OLD_NORM, CANDIDATE_NORM,&
              ORBITAL_OVERLAP, RADIUS_CANDIDATE, RADIUS_OLD,       &
              NODES_CANDIDATE, NODES_OLD, MTP0, MF(J),            &
              E(J)-EOLD, 'accepted_metrics')
      ENDIF
      CALL TRACE_ORBITAL_UPDATE('accepted', 0, J, EOLD, E(J),       &
                                DNORM, ODAMPJ, INV, JP, NNP,       &
                                FALLBACK, .FALSE.)

!   Orthogonalize all orbitals of the same kappa in the order
!   fixed, spectroscopic, correlation orbitals. The order of
!   orbitals in the latter two classes are sorted according
!   to their self-consistency and energy.

      IF (ORTHST) THEN
         !CALL orthor (J, inv)
         NWWW = NW
         CALL ORTHY (NWWW, J, LSORT)
      ENDIF
!
!   Print details of iteration
!
      IF (MYID == 0)                                                &
         WRITE (*, 302) NP(J),NH(J),E(J),METHOD(J),PZ(J),SCNSTY(J), &
!cjb DNORM-1 -> SQRT(DNORM)-1
!cjb                    DNORM - 1, ODAMPJ, JP, MF(J), INV, NNP
                        SQRT(DNORM)-1, ODAMPJ, JP, MF(J), INV, NNP
      DAMPMX = DMAX1(DAMPMX,DABS(ODAMPJ))

  300 FORMAT(/,' Failure; equation for orbital ',1I2,1A2,&
         ' could not be solved using method ',1I1)
  301 FORMAT(/,/,' ****** Error in SUBROUTINE IMPROV ******'/,&
         ' Convergence not obtained'/)
  302 FORMAT (1X,1I2,1A2,1P,1D16.7,1x,1I2,D11.3,1D10.2,1D10.2,&
              0P,F6.3,1x,1I5,1x,1I5,1x,1I2,1x,1I2)
      RETURN
      END SUBROUTINE IMPROVmpi
