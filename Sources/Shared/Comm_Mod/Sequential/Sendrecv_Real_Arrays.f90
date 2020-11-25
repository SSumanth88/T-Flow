!==============================================================================!
  subroutine Comm_Mod_Sendrecv_Real_Arrays(len_s, phi_s,  &
                                           len_r, phi_r, dest)
!------------------------------------------------------------------------------!
!   Dummy function for sequential compilation.                                 !
!------------------------------------------------------------------------------!
  implicit none
!---------------------------------[Arguments]----------------------------------!
  integer :: len_s         ! send length
  real    :: phi_s(len_s)  ! send buffer
  integer :: len_r         ! receive length
  real    :: phi_r(len_r)  ! receive buffer
  integer :: dest          ! destination processor
!==============================================================================!

  end subroutine
