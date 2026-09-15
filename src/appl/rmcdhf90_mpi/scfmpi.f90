!***********************************************************************
!                                                                      *
      SUBROUTINE SCFmpi(EOL, RWFFILE2)
!                                                                      *
!   This  subroutine  performs  the SCF iterations. The procedure is   *
!   essentially algorithm 5.1 of C Froese Fischer, Comput Phys Rep 3   *
!   (1986) 290.                                                        *
!                                                                      *
!   Call(s) to: [LIB92]: ALLOC, DALLOC.                                *
!               [RSCF92]: improvmpi, matrixmpi, MAXARR, newcompi,      *
!                         ORBOUT, ORTHSC, setlagMpi.                   *
!                                                                      *
!   Written by Farid A Parpia, at Oxford    Last update: 22 Dec 1992   *
!   MPI version by Xinghong He            Last revision: 05 Aug 1998   *
!   ifort -i8 version by Alexander Kramida (AK) Last rev. 22 Mar 2016  *
!   Midified by G. Gaigalas                              05 Feb 2017   *
!      It was deleted the arrays:  JQSA(3*NNNWP*NCF),                  *
!                                  JCUPA(NNNWP*NCF)                    *
!                                                                      *
!***********************************************************************
!...Translated by Pacific-Sierra Research 77to90  4.3E  14:16:00   1/ 5/07
!...Modified by Charlotte Froese Fischer
!                     Gediminas Gaigalas  10/05/17
!-----------------------------------------------
!   M o d u l e s
!-----------------------------------------------
      USE vast_kind_param, ONLY:  DOUBLE
      USE, INTRINSIC :: IEEE_ARITHMETIC, ONLY: IEEE_IS_FINITE
      USE memory_man
      USE blkidx_C
      USE default_C
      USE def_C
      USE debug_C
      USE eigv_C
      USE fixd_C
      USE hblock_C
      USE iounit_C
      USE lagr_C
      USE MCPA_C
      USE mpi_C
      USE pos_c
      USE peav_C
      USE ORB_C
      USE orba_C
      USE SCF_C
      USE SYMA_C
      USE STAT_C
      USE ORTHCT_C
      USE ORBOPT_CONTROL_C, ONLY: SET_ORBOPT_ITERATION,             &
                                  STRICT_SCF_CONVERGENCE,            &
                                  SAVE_RWFN_ITERATIONS,              &
                                  ROUND_ROLLBACK_GUARD,              &
                                  MAX_ROUND_ROLLBACKS,               &
                                  MIN_STATE_OVERLAP
      USE ORBOPT_TRACE_C, ONLY: TRACE_SCF_BEGIN, TRACE_SCF_END,     &
                                TRACE_MPI_SUMMARY, CLOSE_ORBOPT_TRACE,&
                                TRACE_ROUND_DECISION, TRACE_ROUND_TARGETS
      USE ORBOPT_ROUND_STATE_C, ONLY: BEGIN_ORBOPT_ROUND,           &
                                      INITIALIZE_FIXED_REFERENCE,    &
                                      CHECK_ORBOPT_ROUND,            &
                                      RESTORE_ORBOPT_ROUND,          &
                                      ACCEPT_ORBOPT_ROUND,           &
                                      REWRITE_ROUND_MIX,             &
                                      END_ORBOPT_ROUND,               &
                                      ROUND_ROLLBACK_COUNT
!-----------------------------------------------
!   I n t e r f a c e   B l o c k s
!-----------------------------------------------
      USE matrixmpi_I
      USE newcompi_I
      USE setlagmpi_I
      USE improvmpi_I
      USE maxarr_I
      USE prwf_I
      USE orthsc_I
      USE orbout_I
      USE endsum_I
      IMPLICIT NONE
!-----------------------------------------------
!   G l o b a l   P a r a m e t e r s
!-----------------------------------------------
!-----------------------------------------------
!   D u m m y   A r g u m e n t s
!-----------------------------------------------
      LOGICAL  :: EOL
      CHARACTER  :: RWFFILE2*(*)
      CHARACTER(LEN=1024) :: RWF_SNAPSHOT
!-----------------------------------------------
!   L o c a l   V a r i a b l e s
!-----------------------------------------------
      INTEGER :: J, I, NIT, JSEQ, KOUNT, K, L_MPI, STRICT_STREAK
      REAL(DOUBLE) :: WTAEV, WTAEV0, DAMPMX
      LOGICAL :: CONVG, CONVG_ENERGY, CONVG_ORBITAL, LSORT, dvdfirst
      LOGICAL :: CONVG_LEGACY, CONVG_STRICT, ENERGY_VALID
      LOGICAL :: ROUND_BAD, ROUND_ORDER_CHANGED, ROUND_NONIDENTITY
      LOGICAL :: ROUND_IDENTITY_STABLE
      REAL(DOUBLE) :: ROUND_MIN_OVERLAP
      CHARACTER(LEN=128) :: ROUND_DETAIL
!-----------------------------------------------
!CFF   .. set the logical variable dvdfirst
      dvdfirst = .true.
!-----------------------------------------------------------------------
!AK Handling the -i8 option of ifort and -fdefault-integer-8 option of gfortran
!      ISIZE = sizeof(NCF)
      L_MPI = MPI_LOGICAL
!      if (ISIZE.EQ.8) L_MPI = MPI_LOGICAL8

      NCFTOT = NCF
      !IF (myid .EQ. 0) PRINT *, '===SCF==='

!=======================================================================
!   Determine Orthonomalization order --- lsort
!=======================================================================

      IF (NDEF == 0) THEN
         LSORT = .FALSE.
      ELSE
         IF (myid .EQ. 0) THEN
  123       CONTINUE
            WRITE (ISTDE, *) 'Orthonomalization order? '
            WRITE (ISTDE, *) '     1 -- Update order'
            WRITE (ISTDE, *) '     2 -- Self consistency connected'
            READ (ISTDI, *) J
            IF (J == 1) THEN
               LSORT = .FALSE.
            ELSE IF (J == 2) THEN
               LSORT = .TRUE.
            ELSE
               WRITE (ISTDE, *) 'Input is wrong, redo...'
               GO TO 123
            ENDIF
         ENDIF
         CALL MPI_Bcast (lsort, 1, L_MPI, 0, MPI_COMM_WORLD, ierr)
      ENDIF

!=======================================================================
!   Deallocate storage that will no longer be used
!=======================================================================

!GG      CALL DALLOC (JQSA, 'JQSA', 'SCFmpi')

!=======================================================================
!   Allocate and fill in auxiliary arrays
!=======================================================================

      CALL ALLOC (NCFPAST, NBLOCK, 'NCFPAST', 'SCFmpi')
      CALL ALLOC (NCMINPAST, NBLOCK, 'NCMINPAST', 'SCFmpi')
      CALL ALLOC (NEVECPAST, NBLOCK, 'NEVECPAST', 'SCFmpi')
      CALL ALLOC (EAVBLK, NBLOCK, 'EAVBLK', 'SCFmpi')

      NCFPAST(1) = 0
      NCMINPAST(1) = 0
      NEVECPAST(1) = 0
      DO I = 2, NBLOCK
         NCFPAST(I) = NCFPAST(I-1) + NCFBLK(I - 1)
         NCMINPAST(I) = NCMINPAST(I-1) + NEVBLK(I - 1)
         NEVECPAST(I) = NEVECPAST(I-1) + NEVBLK(I - 1)*NCFBLK(I - 1)
      END DO

      !*** Size of the eigenvector array for all blocks
      NVECSIZ = NEVECPAST(NBLOCK) + NEVBLK(NBLOCK)*NCFBLK(NBLOCK)

      IF (EOL) THEN
         CALL ALLOC (EVAL, NCMIN, 'EVAL', 'SCFmpi')
         CALL ALLOC (EVEC, NVECSIZ, 'EVEC', 'SCFmpi')
         CALL ALLOC (IATJPO, NCMIN, 'IATJPO', 'SCFmpi')
         CALL ALLOC (IASPAR, NCMIN, 'IASPAR', 'SCFmpi')
      ENDIF

!=======================================================================
!
!=======================================================================
      NDDIM = 64
      NXDIM = 64
      NYDIM = 64
!      NDDIM = 0
!      NYDIM = 0
!      NYDIM = 0
!AK    Must initialize DA,XA,YA,... here since MPI routines rely on their existence in all processes
      CALL ALLOC (NDA, NDDIM, 'NDA','SCFmpi')
      CALL ALLOC (DA, NDDIM, 'DA','SCFmpi')
      CALL ALLOC (NXA, NXDIM, 'NXA','SCFmpi')
      CALL ALLOC (XA, NXDIM, 'XA','SCFmpi')
      CALL ALLOC (NYA, NYDIM, 'NYA','SCFmpi')
      CALL ALLOC (YA, NYDIM, 'YA','SCFmpi')

!     This call should only be made AFTER the call to newco
!     CALL setlag (EOL)

!   For (E)OL calculations, determine the level energies and
!   mixing coefficients

!CFF   .. set the logical variable dvdfirst
      IF (EOL) THEN
         CALL MATRIXmpi (dvdfirst)
         CALL NEWCOmpi (WTAEV)
         CALL INITIALIZE_FIXED_REFERENCE(EOL)
      ENDIF
      WTAEV0 = 0.0
      STRICT_STREAK = 0
      dvdfirst = .false.
      DO NIT = 1, NSCF
         IF (MYID == 0) WRITE (*, 301) NIT
         CALL SET_ORBOPT_ITERATION(NIT)
         CALL TRACE_SCF_BEGIN(NIT, NSCF, NSIC, ACCY, ORTHST, LSORT, &
                              WTAEV0)
         CALL BEGIN_ORBOPT_ROUND(EOL)
         ROUND_IDENTITY_STABLE = .TRUE.

!   For all pairs constrained through a Lagrange multiplier, compute
!   the Lagrange multiplier

         CALL SETLAGmpi (EOL)

!   Improve all orbitals in turn

         DAMPMX = 0.0
         IF (MYID == 0) WRITE (*, 302)
         DO J = 1, NW
            JSEQ = IORDER(J)
            IF (LFIX(JSEQ)) CYCLE
            CALL IMPROVmpi (EOL, JSEQ, LSORT, DAMPMX)
         END DO
!
!   For KOUNT = 1 to NSIC: find the least self-consistent orbital;
!   improve it
!
!         write(istde,*) 'nsic=',nsic
         DO KOUNT = 1, NSIC
            CALL MAXARR (K)
            IF (K == 0) THEN
               CONVG = .TRUE.
               GO TO 3
            ELSE
               IF (SCNSTY(K) <= ACCY) THEN
                  CONVG = .TRUE.
                  GO TO 3
               ENDIF
            ENDIF
            CALL IMPROVmpi (EOL, K, LSORT, DAMPMX)
         END DO

         CALL MAXARR (K)

         IF (K == 0) THEN
            CONVG = .TRUE.
         ELSE
            IF (SCNSTY(K) <= ACCY) THEN
               CONVG = .TRUE.
            ELSE
               CONVG = .FALSE.
            ENDIF
         ENDIF

    3    CONTINUE
         IF (LDBPR(24) .AND. MYID==0) CALL PRWF (0)

!   Perform Gram-Schmidt process
!   For OL calculation, orthst is true and orbitals are orthonormalized
!   in subroutine improv. For AL calculation, orthst is false.
         IF (.NOT.ORTHST) CALL ORTHSC

!   Write the subshell radial wavefunctions to the .rwf file

         IF (MYID == 0) CALL ORBOUT (RWFFILE2)
         IF (MYID == 0 .AND. SAVE_RWFN_ITERATIONS) THEN
            WRITE (RWF_SNAPSHOT,'(A,".iter",I3.3)') TRIM(RWFFILE2), NIT
            CALL ORBOUT(TRIM(RWF_SNAPSHOT))
         ENDIF

         IF (EOL) THEN
            CALL MATRIXmpi(dvdfirst)
            CALL NEWCOmpi (WTAEV)
            IF (.NOT.IEEE_IS_FINITE(WTAEV)) THEN
               IF (MYID == 0) WRITE (ISTDE,'(A,I0)')              &
                  'SCFmpi: non-finite weighted energy at iteration ', NIT
               ERROR STOP 'SCFmpi: non-finite weighted energy'
            ENDIF
         ENDIF

!        Treat the complete orbital update and rediagonalisation as one
!        transaction.  A bad candidate is discarded before it can affect
!        convergence or the next round's weighted-energy reference.
         IF (EOL .AND. ROUND_ROLLBACK_GUARD) THEN
            CALL CHECK_ORBOPT_ROUND(ROUND_BAD, ROUND_MIN_OVERLAP,  &
                 ROUND_ORDER_CHANGED, ROUND_NONIDENTITY, ROUND_DETAIL)
            ROUND_IDENTITY_STABLE = ROUND_MIN_OVERLAP >= MIN_STATE_OVERLAP
            CALL TRACE_ROUND_TARGETS(NIT)
            IF (ROUND_BAD) THEN
               CALL TRACE_ROUND_DECISION(NIT, .FALSE.,             &
                    ROUND_MIN_OVERLAP, ROUND_ORDER_CHANGED,       &
                    ROUND_NONIDENTITY, ROUND_ROLLBACK_COUNT + 1,   &
                    ROUND_DETAIL)
               CALL RESTORE_ORBOPT_ROUND
               ! The candidate was written to the ordinary .rwf/.mix
               ! outputs before it could be checked.  Restore the accepted
               ! state to disk before either continuing or aborting at the
               ! rollback limit; otherwise a failed run leaves a rejected
               ! wavefunction that can be mistaken for a restart input.
               IF (MYID == 0) THEN
                  CALL ORBOUT(RWFFILE2)
                  IF (SAVE_RWFN_ITERATIONS) THEN
                     WRITE (RWF_SNAPSHOT,'(A,".iter",I3.3)')    &
                          TRIM(RWFFILE2), NIT
                     CALL ORBOUT(TRIM(RWF_SNAPSHOT))
                  ENDIF
               ENDIF
               ! Replace the candidate .mix with the accepted snapshot.
               ! Calling MATRIXmpi here would diagonalise and damp again;
               ! REWRITE_ROUND_MIX serialises the saved eigenpairs directly.
               IF (MYID == 0) CALL REWRITE_ROUND_MIX
               IF (ROUND_ROLLBACK_COUNT > MAX_ROUND_ROLLBACKS) THEN
                  IF (MYID == 0) WRITE (ISTDE,'(A,I0)')           &
                     'SCFmpi: round rollback limit exceeded: ',    &
                     ROUND_ROLLBACK_COUNT
                  ERROR STOP 'SCFmpi: round rollback limit exceeded'
               ENDIF
               WTAEV = WTAEV0
               CONVG_ORBITAL = .FALSE.
               CONVG_ENERGY = .FALSE.
               CONVG_LEGACY = .FALSE.
               CONVG_STRICT = .FALSE.
               CONVG = .FALSE.
               ENERGY_VALID = .FALSE.
               ROUND_IDENTITY_STABLE = .FALSE.
               STRICT_STREAK = 0
               CALL TRACE_SCF_END(NIT, CONVG_ORBITAL,             &
                    CONVG_ENERGY, CONVG_LEGACY, CONVG_STRICT,    &
                    CONVG, ENERGY_VALID, STRICT_STREAK,           &
                    ROUND_IDENTITY_STABLE, WTAEV,                &
                    WTAEV0, DAMPMX)
               CALL TRACE_MPI_SUMMARY(NIT)
               CYCLE
            ELSE
               CALL ACCEPT_ORBOPT_ROUND
               CALL TRACE_ROUND_DECISION(NIT, .TRUE.,              &
                    ROUND_MIN_OVERLAP, ROUND_ORDER_CHANGED,        &
                    ROUND_NONIDENTITY, ROUND_ROLLBACK_COUNT,       &
                    'accepted')
            ENDIF
         ENDIF
!        Make this a relative convergence test
!        IF(ABS(WTAEV-WTAEV0).LT.1.0D-9.and.
!    &   DAMPMX.LT.1.0D-4) CONVG=.true.
!        PRINT *, 'WTAEV, WTAEV0', WTAEV, WTAEV0,
!    &             ABS((WTAEV-WTAEV0)/WTAEV)
!GG         IF (ABS((WTAEV - WTAEV0)/WTAEV) < 0.001*ACCY) CONVG = .TRUE.
!cjb unified convergence criteria in RMCDHF and RMCDHF_MPI
!cjb     IF(DABS(WTAEV-WTAEV0).LT.1.0D-8.and.              &
!cjb                   DAMPMX.LT.1.0D-2) CONVG=.true.
         CONVG_ORBITAL = CONVG
!        The first EOL iteration has no previous weighted energy.  Do not
!        let its synthetic WTAEV0=0 value contribute to strict convergence.
         ENERGY_VALID = EOL .AND. NIT > 1 .AND. WTAEV /= 0.D0
         CONVG_ENERGY = .FALSE.
         IF (EOL .AND. WTAEV /= 0.D0)                              &
            CONVG_ENERGY = ABS((WTAEV - WTAEV0)/WTAEV) < 0.001*ACCY
         CONVG_LEGACY = CONVG_ORBITAL .OR. CONVG_ENERGY
         CONVG_STRICT = CONVG_ORBITAL .AND. CONVG_ENERGY .AND.     &
                        ENERGY_VALID .AND. ROUND_IDENTITY_STABLE
         IF (CONVG_STRICT) THEN
            STRICT_STREAK = STRICT_STREAK + 1
         ELSE
            STRICT_STREAK = 0
         ENDIF
         IF (STRICT_SCF_CONVERGENCE) THEN
            CONVG = STRICT_STREAK >= 2
         ELSE
            CONVG = CONVG_LEGACY
         ENDIF
         CALL TRACE_SCF_END(NIT, CONVG_ORBITAL, CONVG_ENERGY,      &
                            CONVG_LEGACY, CONVG_STRICT, CONVG,      &
                            ENERGY_VALID, STRICT_STREAK,            &
                            ROUND_IDENTITY_STABLE, WTAEV,           &
                            WTAEV0, DAMPMX)
         CALL TRACE_MPI_SUMMARY(NIT)
         WTAEV0 = WTAEV
         IF (.NOT.CONVG) CYCLE
         IF (LDBPR(25) .AND. .NOT.LDBPR(24) .AND. MYID==0) CALL PRWF (0)
            !IF (EOL) CALL matrixmpi (dvdfirst)
         GO TO 5

      END DO

      IF (MYID==0) WRITE (ISTDE,*)' Maximum iterations in SCF Exceeded.'

    5 CONTINUE
      DO I = 31, 32 + KMAXF
         CLOSE(I)                                ! The MCP coefficient files
      END DO

      IF (MYID == 0) THEN
         !CLOSE (23)     ! The .rwf file
         CLOSE(25)                               ! The .mix file
      ENDIF
!
!   Complete the summary - moved from rscf92 for easier alloc/dalloc
!
      IF (myid .EQ. 0) CALL ENDSUM
      CALL END_ORBOPT_ROUND
      CALL CLOSE_ORBOPT_TRACE
!
!   Deallocate storage
!
      CALL DALLOC (WT, 'WT', 'SCFmpi')                       !Either getold or getald

      IF (NEC > 0) THEN
         CALL DALLOC (IECC, 'IECC', 'SCFmpi')
         CALL DALLOC (ECV, 'ECV', 'SCFmpi')
         CALL DALLOC (IQA, 'IQA', 'SCFmpi')
      ENDIF

      IF (NDDIM > 0) THEN
         CALL DALLOC (DA, 'DA', 'SCFmpi')
         CALL DALLOC (NDA, 'NDA', 'SCFmpi')
         NDDIM = 0
      ENDIF

      IF (NXDIM > 0) THEN
         CALL DALLOC (XA, 'XA', 'SCFmpi')
         CALL DALLOC (NXA, 'NXA', 'SCFmpi')
         NXDIM = 0
      ENDIF

      IF (NYDIM > 0) THEN
         CALL DALLOC (YA, 'YA', 'SCFmpi')
         CALL DALLOC (NYA, 'NYA', 'SCFmpi')
         NYDIM = 0
      ENDIF

      IF (EOL) THEN
         CALL DALLOC (EVAL, 'EVAL', 'SCFmpi')
         CALL DALLOC (EVEC, 'EvEC', 'SCFmpi')
         CALL DALLOC (IATJPO, 'IATJPO', 'SCFmpi')
         CALL DALLOC (IASPAR, 'IASPAR', 'SCFmpi')
         CALL DALLOC (NCMAXBLK, 'NCMAXBLK', 'SCFmpi') ! getold.f
         CALL DALLOC (EAVBLK, 'EAVBLK', 'SCFmpi')     ! getold.f
         CALL DALLOC (IDXBLK, 'IDXBLK', 'SCFmpi')     ! Allocated in getold.f
         CALL DALLOC (ICCMIN, 'ICCMIN', 'SCFmpi')       ! Allocated in items.f<-getold.f
      ENDIF
!
      CALL DALLOC (NCFPAST, 'NCFPAST', 'SCFmpi')
      CALL DALLOC (NCMINPAST, 'NCMINPAST', 'SCFmpi')
      CALL DALLOC (NEVECPAST, 'NEVECPAST', 'SCFmpi')

  301 FORMAT(/,' Iteration number ',1I3,/,' --------------------')
  302 FORMAT(41X,'Self-            Damping'/,&
         'Subshell    Energy    Method   P0    ',&
         'consistency  Norm-1  factor  JP',' MTP INV NNP'/)

      RETURN
      END SUBROUTINE SCFmpi
