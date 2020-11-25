!==============================================================================!
  subroutine Swarm_Mod_Calculate_Mean(swarm, k, n, n_stat_p, ss)
!------------------------------------------------------------------------------!
!   Calculates particle time averaged velocity                                 !
!------------------------------------------------------------------------------!
  implicit none
!---------------------------------[Arguments]----------------------------------!
  type(Swarm_Type), target :: swarm
  integer, intent(in)      :: k         ! particle index
  integer, intent(in)      :: n         ! current time step (flow time step)
  integer, intent(in)      :: n_stat_p  ! starting time step for swarm statist.
  integer, intent(in)      :: ss        ! sub steo
!-----------------------------------[Locals]-----------------------------------!
  type(Grid_Type),     pointer :: grid
  type(Field_Type),    pointer :: flow
  type(Turb_Type),     pointer :: turb
  type(Particle_Type), pointer :: part
  integer                      :: c, o, l
  real                         :: m
!==============================================================================!

  if(.not. swarm % statistics) return

  ! Take aliases
  grid => swarm % pnt_grid
  flow => swarm % pnt_flow
  turb => swarm % pnt_turb

  l = n - n_stat_p
  if(l > -1) then

    !---------------------------------!
    !   Scale-resolving simulations   !
    !---------------------------------!
    if(turb % model .eq. LES_SMAGORINSKY    .or.  &
       turb % model .eq. LES_DYNAMIC        .or.  &
       turb % model .eq. LES_WALE           .or.  &
       turb % model .eq. HYBRID_LES_PRANDTL .or.  &
       turb % model .eq. HYBRID_LES_RANS    .or.  &
       turb % model .eq. DES_SPALART        .or.  &
       turb % model .eq. DNS) then

      ! Take alias for the particle
      part => swarm % particle(k)

      ! Cell in which the current particle resides
      c = swarm % particle(k) % cell

      ! Current number of states (for swarm quantity averaging) 
      m = real(swarm % n_states(c))

      ! Mean velocities for swarm
      swarm % u_mean(c) = (swarm % u_mean(c) * m + part % u) / (m+1)
      swarm % v_mean(c) = (swarm % v_mean(c) * m + part % v) / (m+1)
      swarm % w_mean(c) = (swarm % w_mean(c) * m + part % w) / (m+1)

      ! Resolved Reynolds stresses
      swarm % uu(c) = (swarm % uu(c) * m + part % u * part % u) / (m+1)
      swarm % vv(c) = (swarm % vv(c) * m + part % v * part % v) / (m+1)
      swarm % ww(c) = (swarm % ww(c) * m + part % w * part % w) / (m+1)

      swarm % uv(c) = (swarm % uv(c) * m + part % u * part % v) / (m+1)
      swarm % uw(c) = (swarm % uw(c) * m + part % u * part % w) / (m+1)
      swarm % vw(c) = (swarm % vw(c) * m + part % v * part % w) / (m+1)

      ! Increase the number of states of the cell
      swarm % n_states(c) = swarm % n_states(c) + 1

    end if
  end if

  end subroutine
