!==============================================================================!
  subroutine Grid_Mod_Calculate_Weights_Nodes_To_Cells(grid)
!------------------------------------------------------------------------------!
!   Computes weights for interpolation from nodes to cells                     !
!------------------------------------------------------------------------------!
  implicit none
!---------------------------------[Arguments]----------------------------------!
  type(Grid_Type) :: grid
!-----------------------------------[Locals]-----------------------------------!
  integer :: c, n, i_nod
  real    :: lx, ly, lz, rx, ry, rz, lambda_x, lambda_y, lambda_z
  real    :: ixx, iyy, izz, ixz, iyz, ixy, d
  real    :: a11, a12, a13, a21, a22, a23, a31, a32, a33
  real    :: tot
  ! Debugging: real    :: weights_sorted(64)
!==============================================================================!

  ! Allocate memory
  allocate(grid % weight_n2c(size(grid % cells_n,1),  &
                                 size(grid % cells_n,2)))
  grid % weight_n2c = 0.0

  !-------------------------------------------!
  !   Browse through all cells to calculate   !
  !     weights from nodes surrounding it     !
  !-------------------------------------------!
  do c = 1, grid % n_cells
    rx = 0.0; ry = 0.0; rz = 0.0
    ixx = 0.0; iyy = 0.0; izz = 0.0; ixz = 0.0; iyz = 0.0; ixy = 0.0

    ! Loop on nodes of the cell
    do i_nod = 1, abs(grid % cells_n_nodes(c))
      n   = grid % cells_n(i_nod, c)
      lx  = grid % xn(n) - grid % xc(c)
      ly  = grid % yn(n) - grid % yc(c)
      lz  = grid % zn(n) - grid % zc(c)
      rx  = rx  + lx
      ry  = ry  + ly
      rz  = rz  + lz
      ixx = ixx + lx ** 2
      iyy = iyy + ly ** 2
      izz = izz + lz ** 2
      ixy = ixy + lx * ly
      ixz = ixz + lx * lz
      iyz = iyz + ly * lz
    end do

    a11 = iyy * izz - iyz ** 2
    a12 = ixz * iyz - ixy * izz
    a13 = ixy * iyz - ixz * iyy
    a21 = ixz * iyz - ixy * izz
    a22 = ixx * izz - ixz ** 2
    a23 = ixy * ixz - ixx * iyz
    a31 = ixy * iyz - ixz * iyy
    a32 = ixz * ixy - ixx * iyz
    a33 = ixx * iyy - ixy ** 2

    d = ixx * iyy * izz - ixx * iyz **2 - iyy * ixz ** 2 - izz * ixy ** 2   &
      + 2.0 * ixy * ixz * iyz

    lambda_x = (rx * a11 + ry * a12 + rz * a13) / (d + FEMTO)
    lambda_y = (rx * a21 + ry * a22 + rz * a23) / (d + FEMTO)
    lambda_z = (rx * a31 + ry * a32 + rz * a33) / (d + FEMTO)

    do i_nod = 1, abs(grid % cells_n_nodes(c))
      n = grid % cells_n(i_nod, c)
      lx  = grid % xn(n) - grid % xc(c)
      ly  = grid % yn(n) - grid % yc(c)
      lz  = grid % zn(n) - grid % zc(c)
      grid % weight_n2c(i_nod, c) = 1.0             &
                                      + lambda_x * lx   &
                                      + lambda_y * ly   &
                                      + lambda_z * lz
    end do

  end do  ! through cells

  !---------------------------!
  !   Normalize the weights   !
  !---------------------------!
  do c = 1, grid % n_cells

    ! Loop on nodes
    tot = 0.0
    do i_nod = 1, abs(grid % cells_n_nodes(c))
      tot = tot + grid % weight_n2c(i_nod, c)
    end do

    ! Loop on nodes
    do i_nod = 1, abs(grid % cells_n_nodes(c))
      grid % weight_n2c(i_nod, c) = grid % weight_n2c(i_nod, c) / tot
    end do

  end do

  end subroutine
