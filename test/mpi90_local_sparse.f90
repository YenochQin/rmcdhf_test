! Check the real MPI sparse kernels against a dense matrix.  Only the
! collective is replaced: SPICMV returns each local contribution for summing
! here; INIEST's local packed matrix is checked before supplying the global
! packed matrix to LAPACK.  This tests storage semantics without launching MPI.
module sparse_reduction_check
    use vast_kind_param, only: double
    use mpi_C, only: myid, nprocs
    implicit none
    integer, parameter :: matrix_size = 8
    real(double) :: dense(matrix_size, matrix_size)
    integer :: packed_size = 0
    real(double) :: packed_error = 0.d0
contains
    subroutine check_reduction(x, n)
        integer, intent(in) :: n
        real(double), intent(inout) :: x(n)
        integer :: i, j, k
        real(double) :: expected_local

        if (packed_size == 0) return
        if (n /= packed_size * (packed_size + 1) / 2) error stop 'packed size'
        k = 0
        do j = 1, packed_size
            do i = 1, j
                k = k + 1
                expected_local = 0.d0
                if (mod(j - 1, nprocs) == myid) expected_local = dense(i, j)
                packed_error = max(packed_error, abs(x(k) - expected_local))
                x(k) = dense(i, j)
            end do
        end do
    end subroutine check_reduction
end module sparse_reduction_check

subroutine gdsummpi(x, n)
    use sparse_reduction_check, only: double, check_reduction
    implicit none
    integer, intent(in) :: n
    real(double), intent(inout) :: x(n)
    call check_reduction(x, n)
end subroutine gdsummpi

program mpi90_local_sparse
    use sparse_reduction_check
    use hmat_C, only: emt, irow, iendc, nelmnt
    use mpi_C, only: ierr
    use spicmvmpi_I, only: spicmvmpi
    use iniestmpi_I, only: iniestmpi
    implicit none
    integer, parameter :: rhs_count = 3, root_count = 2
    integer, parameter :: rank_counts(*) = [1, 2, 3, 4, 46]
    real(double) :: rhs(matrix_size, rhs_count), local(matrix_size, rhs_count)
    real(double) :: total(matrix_size, rhs_count), product_error, eigen_error
    real(double) :: basis((matrix_size + 1) * root_count), vector(matrix_size)
    real(double) :: eigenvalue
    integer :: i, j, k, count_index, mode, nmax, niv, root, failures

    dense = 0.d0
    do i = 1, matrix_size
        dense(i, i) = 2.d0 * i
    end do
    ! Unequal column lengths, diagonals only in some columns, and distant
    ! couplings expose reuse of entries from an earlier local column.
    dense(1, 2) = 0.3d0
    dense(1, 4) = -0.2d0
    dense(3, 4) = 0.4d0
    dense(2, 5) = 0.1d0
    dense(1, 7) = 0.6d0
    dense(4, 7) = -0.3d0
    dense(3, 8) = 0.2d0
    do j = 1, matrix_size
        do i = 1, j - 1
            dense(j, i) = dense(i, j)
        end do
        do k = 1, rhs_count
            rhs(j, k) = real(j - 2 * k, double) / 7.d0
        end do
    end do

    allocate(iendc(0:matrix_size), irow(matrix_size**2), emt(matrix_size**2))
    failures = 0
    do count_index = 1, size(rank_counts)
        nprocs = rank_counts(count_index)
        total = 0.d0
        packed_error = 0.d0
        eigen_error = 0.d0
        do myid = 0, nprocs - 1
            ! MATRIXmpi reads endpoints only for the columns owned by this
            ! rank.  Its EMT/IROW contain just those columns, packed together.
            iendc = 0
            emt = 0.d0
            irow = 1
            k = 0
            do j = myid + 1, matrix_size, nprocs
                do i = 1, j
                    if (dense(i, j) == 0.d0) cycle
                    k = k + 1
                    emt(k) = dense(i, j)
                    irow(k) = i
                end do
                iendc(j) = k
            end do
            nelmnt = k

            packed_size = 0
            call spicmvmpi(matrix_size, rhs_count, rhs, local)
            total = total + local

            ! Full and truncated initial subspaces, including ranks with no
            ! columns, exercise the INIEST caller's two size regimes.
            do mode = 1, 2
                nmax = matrix_size
                if (mode == 2) nmax = 5
                packed_size = nmax
                niv = root_count
                call iniestmpi(nmax, matrix_size, niv, basis, emt, iendc, irow)
                if (ierr /= 0) error stop 'INIEST LAPACK failure'
                do root = 1, root_count
                    vector = basis((root - 1) * matrix_size + 1 : root * matrix_size)
                    eigenvalue = basis(root_count * matrix_size + root)
                    eigen_error = max(eigen_error, maxval(abs( &
                        matmul(dense(:nmax, :nmax), vector(:nmax)) - eigenvalue * vector(:nmax))))
                    eigen_error = max(eigen_error, abs(dot_product(vector, vector) - 1.d0))
                    if (nmax < matrix_size) eigen_error = max(eigen_error, maxval(abs(vector(nmax + 1:))))
                end do
            end do
        end do
        product_error = maxval(abs(total - matmul(dense, rhs)))
        write(*, '(A,I0,3(A,ES12.4))') 'partitions=', nprocs, &
            ' matmul_error=', product_error, ' packed_error=', packed_error, ' eigen_residual=', eigen_error
        if (max(product_error, packed_error, eigen_error) > 1.d-10) failures = failures + 1
    end do
    deallocate(iendc, irow, emt)
    if (failures > 0) error stop 'rank-local sparse storage mismatch'
end program mpi90_local_sparse
