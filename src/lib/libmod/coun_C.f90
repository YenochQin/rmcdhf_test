      MODULE coun_C
      USE vast_kind_param, ONLY:  DOUBLE
!...Created by Pacific-Sierra Research 77to90  4.3E  11:02:52   1/ 2/07
!...Modified by Charlotte Froese Fischer
!                     Gediminas Gaigalas  10/05/17
      REAL(DOUBLE) :: THRESH
      INTEGER :: COUNT_CONTEXT = 0
!     Every rank replicates the radial solve and shares one rmcdhf.log, so
!     the node trace is written by one rank only.  Serial callers leave this
!     at 0 and keep tracing.
      INTEGER :: COUNT_TRACE_RANK = 0
      END MODULE coun_C
