!==============================================================================!
  real function Correct_Velocity(flow, mult, sol, dt, ini)
!------------------------------------------------------------------------------!
!   Corrects the velocities, and mass (or volume) fluxes on cell faces.        !
!------------------------------------------------------------------------------!
!----------------------------------[Modules]-----------------------------------!
  use User_Mod
!------------------------------------------------------------------------------!
  implicit none
!---------------------------------[Arguments]----------------------------------!
  type(Field_Type),      target :: flow
  type(Multiphase_Type), target :: mult
  type(Solver_Type),     target :: sol
  real                          :: dt
  integer                       :: ini
!-----------------------------------[Locals]-----------------------------------!
  type(Grid_Type),   pointer :: grid
  type(Bulk_Type),   pointer :: bulk
  type(Var_Type),    pointer :: u, v, w, p, pp
  type(Face_Type),   pointer :: v_flux          ! volume flux
  type(Matrix_Type), pointer :: a
  real,              pointer :: b(:)
  real,              pointer :: u_relax
  integer                    :: c, c1, c2, s
  real                       :: cfl_t, pe_t, mass_err
  real                       :: dens_f, visc_f
!==============================================================================!

  call Cpu_Timer_Mod_Start('Correct_Velocity')

  ! Take aliases
  grid    => flow % pnt_grid
  bulk    => flow % bulk
  v_flux  => flow % v_flux
  p       => flow % p
  pp      => flow % pp
  a       => sol % a
  b       => sol % b % val
  u_relax => flow % u_rel_corr

  call Field_Mod_Alias_Momentum(flow, u, v, w)

  ! User function
  call User_Mod_Beginning_Of_Correct_Velocity(flow, mult, sol, dt, ini)

  !-----------------------------------------!
  !   Correct velocities and fluxes with    !
  !    periodic part of the pressure to     !
  !    obtain divergence free velocity      !
  !-----------------------------------------!
  do c = 1, grid % n_cells
    u % n(c) = u % n(c) - u_relax * pp % x(c) * grid % vol(c) / a % sav(c)
    v % n(c) = v % n(c) - u_relax * pp % y(c) * grid % vol(c) / a % sav(c)
    w % n(c) = w % n(c) - u_relax * pp % z(c) * grid % vol(c) / a % sav(c)
  end do

  do s = 1, grid % n_faces
    c1 = grid % faces_c(1,s)
    c2 = grid % faces_c(2,s)

    if(c2  < 0) then
      if( (Grid_Mod_Bnd_Cond_Type(grid,c2) .eq. PRESSURE) ) then
        u % n(c2) = u % n(c1)
        v % n(c2) = v % n(c1)
        w % n(c2) = w % n(c1)
      end if
    end if
  end do
  call Field_Mod_Grad_Variable(flow, u)
  call Field_Mod_Grad_Variable(flow, v)
  call Field_Mod_Grad_Variable(flow, w)

  !----------------------------------------------------------------!
  !   Look at the following equation and you will understand why   !
  !   is the matrix for pressure corrections in SIMPLE algorithm   !
  !   formed from the coefficients of the velocity matrix.         !
  !                                                                !
  !   Note that the fluxes corrected below are either mass or      !
  !   volume fluxes, depending on how the right hand side term     !
  !   for pressure was formed.                                     !
  !----------------------------------------------------------------!
  do s = 1, grid % n_faces
    c1 = grid % faces_c(1,s)
    c2 = grid % faces_c(2,s)
    if(c2 > 0) then
                                     !<--- this is correction --->!
      v_flux % n(s) = v_flux % n(s) + ( pp % n(c2) - pp % n(c1) )   &
                                       * a % val(a % pos(1,s))

    end if
  end do

  !-------------------------------------!
  !    Calculate the max mass error     !
  !   with the new (corrected) fluxes   !
  !-------------------------------------!

  if(flow % p_m_coupling == SIMPLE) then
    do c = 1, grid % n_cells
      b(c) = 0.0
    end do

    do s = 1, grid % n_faces
      c1 = grid % faces_c(1,s)
      c2 = grid % faces_c(2,s)

      b(c1) = b(c1) - v_flux % n(s)
      if(c2 > 0) then
        b(c2) = b(c2) + v_flux % n(s)
      end if
    end do

    if(mult % model .eq. VOLUME_OF_FLUID) then
      if(mult % phase_change) then
        do c = 1, grid % n_cells
          b(c) = b(c) + mult % flux_rate(c) * grid % vol(c)                 &
                                            * ( 1.0 / mult % phase_dens(1)  &
                                              - 1.0 / mult % phase_dens(2) )
        end do
      end if

      !do c = 1, grid % n_cells
      !  !if (grid % xc(c) > 0.0001 .and. grid % xc(c) < 0.00012) then
      !    b(c) = b(c) - mult % flux_rate(c) / flow % density(c)
      !end do

      do c = 1, grid % n_cells
        b(c) = b(c) / (grid % vol(c) / dt)
      end do

    else
      !do c = 1, grid % n_cells
      !  if (grid % xc(c) > 0.0001 .and. grid % xc(c) < 0.00012) then
      !  !if (grid % xc(c) > 3.87 .and. grid % xc(c) < 3.92) then
      !    b(c) = b(c) + 1.0e-10
      !  end if
      !end do
      do c = 1, grid % n_cells
        b(c) = b(c) / (flow % density(c) * grid % vol(c) / dt)
      end do
    end if

    mass_err = 0.0
    do c = 1, grid % n_cells - grid % comm % n_buff_cells
      mass_err = max(mass_err, abs(b(c)))
    end do
  else
    mass_err = p % res
  end if


  call Comm_Mod_Global_Max_Real(mass_err)

  !------------------------------!
  !   Calculate the CFL number   !
  !     and the Peclet number    !
  !------------------------------!
  flow % cfl_max = 0.0
  flow % pe_max  = 0.0
  do s = 1, grid % n_faces
    c1 = grid % faces_c(1,s)
    c2 = grid % faces_c(2,s)
    dens_f =        grid % fw(s)  * flow % density  (c1)   &
           + (1.0 - grid % fw(s)) * flow % density  (c2)
    visc_f =        grid % fw(s)  * flow % viscosity(c1)   &
           + (1.0 - grid % fw(s)) * flow % viscosity(c2)
    if(c2 > 0) then
      cfl_t = abs( dt * v_flux % n(s) /          &
                   ( a % fc(s) *                 &
                   (  grid % dx(s)*grid % dx(s)  &
                    + grid % dy(s)*grid % dy(s)  &
                    + grid % dz(s)*grid % dz(s)) ) )
      pe_t    = abs( v_flux % n(s) / a % fc(s) / (visc_f / dens_f + TINY) )
      flow % cfl_max = max( flow % cfl_max, cfl_t )
      flow % pe_max  = max( flow % pe_max,  pe_t  )
    end if
  end do
  call Comm_Mod_Global_Max_Real(flow % cfl_max)
  call Comm_Mod_Global_Max_Real(flow % pe_max)

  if (flow % p_m_coupling == SIMPLE) then
    call Info_Mod_Iter_Fill_At(1, 5, 'dum', -1, mass_err)
  else
    if (flow % i_corr == flow % n_piso_corrections) then
      call Info_Mod_Iter_Fill_At(1, 5, 'dum', -1, mass_err)
    end if
  end if

  Correct_Velocity = mass_err ! /(velmax+TINY)

  ! User function
  call User_Mod_End_Of_Correct_Velocity(flow, mult, sol, dt, ini)

  call Cpu_Timer_Mod_Stop('Correct_Velocity')

  end function
