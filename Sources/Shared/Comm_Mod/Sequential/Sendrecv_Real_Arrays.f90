!==============================================================================!
  subroutine Comm_Mod_Sendrecv_Real_Arrays(phi_s, len_s,  &
                                           phi_r, len_r, dest)
!------------------------------------------------------------------------------!
!   Dummy function for sequential compilation.                                 !
!------------------------------------------------------------------------------!
  implicit none
!---------------------------------[Arguments]----------------------------------!
  real    :: phi_s(len_s)  ! send buffer
  integer :: len_s         ! send length
  real    :: phi_r(len_r)  ! receive buffer
  integer :: len_r         ! receive length
  integer :: dest          ! destination processor
!==============================================================================!

  end subroutine
