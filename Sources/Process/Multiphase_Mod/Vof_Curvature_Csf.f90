!==============================================================================!
  subroutine Multiphase_Mod_Vof_Curvature_Csf(grid, mult,                  &
                                              grad_kx, grad_ky, grad_kz,   &
                                              curr_colour)
!------------------------------------------------------------------------------!
!   Computes the Curvature based on Brackbill's CSF using Least Squares method !
!   or Gauss theorem                                                           !
!                                                                              !
!   Arguments:                                                                 !
!   - grad_kx, grad_ky, grad_kz: gradient components of curr_colour            !
!   - curr_colour              : it can be the distance function or vof.       !
!                                In any case, they have been smoothed out      !
!                                previously to enhance curvature calculation   !
!------------------------------------------------------------------------------!
!----------------------------------[Modules]-----------------------------------!
  use Work_Mod, only: div_x => r_cell_10,  &
                      div_y => r_cell_11,  &
                      div_z => r_cell_12,  &
                      vof_n => r_node_01,  &
                      c_ind => i_cell_02
!------------------------------------------------------------------------------!
  implicit none
!---------------------------------[Arguments]----------------------------------!
  type(Multiphase_Type), target :: mult
  type(Grid_Type)               :: grid
  real                          :: grad_kx    (-grid % n_bnd_cells    &
                                              : grid % n_cells),      &
                                   grad_ky    (-grid % n_bnd_cells    &
                                              : grid % n_cells),      &
                                   grad_kz    (-grid % n_bnd_cells    &
                                              : grid % n_cells),      &
                                   curr_colour(-grid % n_bnd_cells    &
                                              : grid % n_cells)
!-----------------------------------[Locals]-----------------------------------!
  type(Field_Type), pointer :: flow
  type(Var_Type),   pointer :: vof
  integer                   :: s, c, c1, c2, n, i_fac,i_nod, tot_cells,sub
  integer                   :: c_inte, fu, nb, nc
  integer                   :: avgi, n_avg, icell, cc
  real, contiguous, pointer :: fs_x(:), fs_y(:), fs_z(:)
  real                      :: vol_face, grad_face(3), d_n(3)
  real                      :: dotprod, sxyz_mod, sxyz_control, fs, epsloc
  real                      :: dotprod2, stabilize
  real                      :: n_0(3), n_f(3), n_w(3), reflex(3)
  real                      :: theta, theta0, a, b, s_vector(3)
  real                      :: vof_fx, vof_fy, vof_fz, vof_c1, vof_c2, voff
  real                      :: res1, res2, resul, term_c, sumtot
  real                      :: sumx, sumy, sumz, norm_grad, coeff
  real                      :: v1(3), v2(3), v3(3), v4(3)
  real                      :: gf_x, gf_y, gf_z, curv_loc
  real                      :: costheta0, costheta, a1, a2
  real                      :: avg_curv, sum_neigh
!==============================================================================!

  vof  => mult % vof
  flow => mult % pnt_flow

  nb = grid % n_bnd_cells
  nc = grid % n_cells

  epsloc = epsilon(epsloc)

  ! At Boundaries
  do s = 1, grid % n_bnd_faces
    c1 = grid % faces_c(1,s)
    c2 = grid % faces_c(2,s)
    if (Grid_Mod_Bnd_Cond_Type(grid,c2) .eq. WALL) then
      gf_x = grad_kx(c1)
      gf_y = grad_ky(c1)
      gf_z = grad_kz(c1)

      norm_grad = norm2((/gf_x, gf_y, gf_z/))

      gf_x = gf_x / (norm_grad + epsloc)
      gf_y = gf_y / (norm_grad + epsloc)
      gf_z = gf_z / (norm_grad + epsloc)

      costheta0 = dot_product((/gf_x, gf_y, gf_z/),                          &
                              (/grid % sx(s), grid % sy(s), grid % sz(s)/))  &
                 / grid % s(s)
      theta0 = acos(costheta0)

      theta = vof % q(c2) * PI /180.0
      costheta = cos(theta)

      a1 = cos(theta0 - theta)
      a2 = 1.0 - costheta0 * costheta0

      a = (costheta - costheta0 * a1) / (a2 + epsloc)
      b = (a1 - costheta0 * costheta) / (a2 + epsloc)

      grad_kx(c1) = b * gf_x + a * grid % sx(s) / grid % s(s)
      grad_ky(c1) = b * gf_y + a * grid % sy(s) / grid % s(s)
      grad_kz(c1) = b * gf_z + a * grid % sz(s) / grid % s(s)
      grad_kx(c2) = grad_kx(c1)
      grad_ky(c2) = grad_ky(c1)
      grad_kz(c2) = grad_kz(c1)

    else if(Grid_Mod_Bnd_Cond_Type(grid,c2) .eq. SYMMETRY) then

      norm_grad = norm2((/grad_kx(c1),grad_ky(c1),grad_kz(c1)/))

      if (norm_grad > epsloc) then
        v1 = (/grid % sx(s), grid % sy(s), grid % sz(s)/)
        v2 = (/grad_kx(c1), grad_ky(c1), grad_kz(c1)/)
        v3 = Math_Mod_Cross_Product(v1, v2)
        v4 = Math_Mod_Cross_Product(v3, v1)
        ! projection on v4
        norm_grad = norm2(v4)
        if (norm_grad > epsloc) then
          grad_kx(c2) = v4(1) / norm_grad
          grad_ky(c2) = v4(2) / norm_grad
          grad_kz(c2) = v4(3) / norm_grad
        end if
      end if
    else
      grad_kx(c2) = grad_kx(c1)
      grad_ky(c2) = grad_ky(c1)
      grad_kz(c2) = grad_kz(c1)
    end if

  end do

  call Grid_Mod_Exchange_Cells_Real(grid, grad_kx(-nb:nc))
  call Grid_Mod_Exchange_Cells_Real(grid, grad_ky(-nb:nc))
  call Grid_Mod_Exchange_Cells_Real(grid, grad_kz(-nb:nc))

  !--------------------!
  !   Find Curvature   !
  !--------------------!

  mult % curv = 0.0

  if(mult % least_squares_curvature) then

    ! Normalize vector at cells
    do c = -nb, nc
      norm_grad = norm2((/grad_kx(c), grad_ky(c), grad_kz(c)/))
      grad_kx(c) = grad_kx(c) / (norm_grad + epsloc)
      grad_ky(c) = grad_ky(c) / (norm_grad + epsloc)
      grad_kz(c) = grad_kz(c) / (norm_grad + epsloc)
    end do

    ! Find divergence of normals
    call Field_Mod_Grad_Component(flow, grad_kx(-nb:nc), 1, div_x(-nb:nc))
    call Field_Mod_Grad_Component(flow, grad_ky(-nb:nc), 2, div_y(-nb:nc))
    call Field_Mod_Grad_Component(flow, grad_kz(-nb:nc), 3, div_z(-nb:nc))

    mult % curv(-nb:nc) = mult % curv(-nb:nc) - div_x(-nb:nc)
    mult % curv(-nb:nc) = mult % curv(-nb:nc) - div_y(-nb:nc)
    mult % curv(-nb:nc) = mult % curv(-nb:nc) - div_z(-nb:nc)

    call Grid_Mod_Exchange_Cells_Real(grid, mult % curv)

  else ! Divergence theorem method

    ! Normalize vector at cells
    do c = -nb, nc
      norm_grad = norm2((/grad_kx(c), grad_ky(c), grad_kz(c)/))
      grad_kx(c) = grad_kx(c) / (norm_grad + epsloc)
      grad_ky(c) = grad_ky(c) / (norm_grad + epsloc)
      grad_kz(c) = grad_kz(c) / (norm_grad + epsloc)
    end do

    ! Boundary faces
    do s = 1, grid % n_bnd_faces
      c1 = grid % faces_c(1,s)
      c2 = grid % faces_c(2,s)
      if (Grid_Mod_Bnd_Cond_Type(grid,c2) .eq. SYMMETRY) then
        grad_face(1) = grad_kx(c2)
        grad_face(2) = grad_ky(c2)
        grad_face(3) = grad_kz(c2)
      else
        grad_face(1) = grad_kx(c1)
        grad_face(2) = grad_ky(c1)
        grad_face(3) = grad_kz(c1)
      end if

      sxyz_mod = norm2((/grad_face(1), grad_face(2), grad_face(3)/))

      dotprod = (grad_face(1) * grid % sx(s)                            &
               + grad_face(2) * grid % sy(s)                            &
               + grad_face(3) * grid % sz(s)) / ( sxyz_mod + epsloc )

      sxyz_control = norm2((/vof % x(c1),vof % y(c1),vof % z(c1)/))

      if (sxyz_control > epsloc) then
        mult % curv(c1) = mult % curv(c1) + dotprod
      end if
    end do

    ! Interior faces
    do s = grid % n_bnd_faces + 1, grid % n_faces
      c1 = grid % faces_c(1,s)
      c2 = grid % faces_c(2,s)
      fs = grid % f(s)

      grad_face(1) = fs * grad_kx(c1) + (1.0 - fs) * grad_kx(c2)
      grad_face(2) = fs * grad_ky(c1) + (1.0 - fs) * grad_ky(c2)
      grad_face(3) = fs * grad_kz(c1) + (1.0 - fs) * grad_kz(c2)

      sxyz_mod = sqrt(grad_face(1) ** 2  &
                    + grad_face(2) ** 2  &
                    + grad_face(3) ** 2)

      dotprod = (grad_face(1) * grid % sx(s)  &
               + grad_face(2) * grid % sy(s)  &
               + grad_face(3) * grid % sz(s)) / ( sxyz_mod + epsloc )

      sxyz_control = norm2((/vof % x(c1),vof % y(c1),vof % z(c1)/))

      if (sxyz_control > epsloc) then
        mult % curv(c1) = mult % curv(c1) + dotprod
      end if

      sxyz_control = norm2((/vof % x(c2),vof % y(c2),vof % z(c2)/))

      if (sxyz_control > epsloc) then
        mult % curv(c2) = mult % curv(c2) - dotprod
      end if

    end do

    call Grid_Mod_Exchange_Cells_Real(grid, mult % curv)

    do c = 1, grid % n_cells
      mult % curv(c) = - mult % curv(c) / grid % vol(c)
    end do

  end if

  ! At boundaries
  do s = 1, grid % n_bnd_faces
    c1 = grid % faces_c(1,s)
    c2 = grid % faces_c(2,s)
    mult % curv(c2) = mult % curv(c1)
  end do

  call Multiphase_Mod_Vof_Smooth_Curvature(grid, mult,                  &
                          grad_kx(-nb:nc), grad_ky(-nb:nc), grad_kz(-nb:nc))

  call Grid_Mod_Exchange_Cells_Real(grid, mult % curv)

  end subroutine
