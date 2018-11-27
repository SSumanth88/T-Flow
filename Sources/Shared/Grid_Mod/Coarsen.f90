!==============================================================================!
  subroutine Grid_Mod_Coarsen(grid)
!------------------------------------------------------------------------------!
!   Coarsens the grid with METIS library.                                      !
!------------------------------------------------------------------------------!
  implicit none
!---------------------------------[Arguments]----------------------------------!
  type(Grid_Type) :: grid
!-----------------------------------[Locals]-----------------------------------!
  integer              :: c, c1, c2, nc, nc1, nc2, s, i, lev, lev_parts
  integer              :: n_cells, n_faces, arr_s, arr_e, val_1, val_2
  integer              :: c_lev, c1_lev, c2_lev, s_lev
  integer, allocatable :: c1_arr(:), c2_arr(:), sf_arr(:)
  integer, allocatable :: cells_c(:,:), cells_n_cells(:), faces_c(:,:),  &
                          new_c(:), old_c(:),                            &
                          cell_mapping(:,:)

! Variabes for call to METIS
  integer              :: n_constrains,      &  ! number of constraints
                          return_val            ! return value from METIS
  integer, allocatable :: row(:),            &  ! incidency matrix in ...
                          col(:),            &  ! compresser row format
                          cell_weights(:),   &  ! weights of vertices
                          face_weights(:),   &  ! weights of edges
                          vert_data(:),      &  ! amount of data for vertices
                          part(:)               ! result of partitioning
  real, allocatable    :: part_weight(:),    &
                          imbalance(:)          ! allowed imbalance
  integer              :: metis_options(41)     ! options passed to METIS
!==============================================================================!

  print *, '#=========================================='
  print *, '# Coarsening the grid for multigrid solver '
  print *, '#------------------------------------------'

  !---------------------!
  !                     !
  !   Allocate memory   !
  !                     !
  !---------------------!

  allocate(new_c(grid % n_cells))
  allocate(old_c(grid % n_cells))

  ! Number of cells (vertices for METIS) and number of faces ...
  ! ... inside the grid (edges for METIS) for the first level
  n_cells = grid % n_cells
  n_faces = 0
  do s = 1, grid % n_faces
    c2 = grid % faces_c(2,s)
    if(grid % faces_c(2,s) > 0) n_faces = n_faces + 1
  end do

  !---------------------------------------------------------!
  !   Once n_cells and n_faces are known, allocate memory   !
  !---------------------------------------------------------!
  allocate(faces_c      ( 2,n_faces));  faces_c      (:,:) = 0
  allocate(cells_n_cells(   n_cells));  cells_n_cells(:)   = 0
  allocate(cells_c      (24,n_cells));  cells_c      (:,:) = 0
  allocate(part         (   n_cells));  part         (:)   = 1
  allocate(row          ( 1+n_cells))
  allocate(col          ( 2*n_faces))

  allocate(c1_arr(n_faces))
  allocate(c2_arr(n_faces))
  allocate(sf_arr(n_faces))

  !------------------------------------------------------!
  !   Allocate memory for control parameters for METIS   !
  !------------------------------------------------------!
  n_constrains = 1
  allocate(imbalance   (n_constrains))
  allocate(cell_weights(n_cells * n_constrains))
  allocate(face_weights(n_faces + n_faces))
  allocate(vert_data   (n_cells))
  allocate(part_weight (N_MG_PARTS * n_constrains))

  !--------------------------------------------------------!
  !   Allocate memory and initialize data for all levels   !
  !--------------------------------------------------------!

  ! Count levels and cells
  do lev = 2, MAX_MG_LEVELS
    if(N_MG_PARTS**(lev-1) > grid % n_cells/N_MG_PARTS) then
      grid % n_levels = lev
      goto 1
    end if
  end do
  grid % n_levels = MAX_MG_LEVELS
1 continue

  ! Perform allocation and initialization
  call Grid_Mod_Create_Levels(grid)

  print '(a29,i2,a8)', ' # Will perform coarsening in',  &
                       grid % n_levels, ' levels.'

  !---------------------------!
  !                           !
  !                           !
  !   Browse through levels   !
  !                           !
  !                           !
  !---------------------------!
  do lev = grid % n_levels, 2, -1  ! goes from the coarsest (highest number)
                                   ! to the finest (lower number and zero)

    lev_parts = N_MG_PARTS ** (grid % n_levels - lev)

    print '(a19,i2,a7,i7,a7)', ' # Working on level',                      &
                               lev,                                        &
                               ' with  ',                                  &
                               N_MG_PARTS ** (grid % n_levels - lev + 1),  &
                               ' cells.'

    !---------------------------------------------!
    !   Through exising partitions on level lev   !
    !---------------------------------------------!
    new_c(:) = 0
    old_c(:) = 0
    do c_lev = 1, lev_parts

      ! Mark cells in current partition
      i = 0
      do c = 1, grid % n_cells
        if(grid % level(lev+1) % cell(c) .eq. c_lev) then
          i = i + 1
          new_c(c) = i
          old_c(i) = c
        end if
      end do
      n_cells = i

      ! Form face (edge for METIS) connectivity in ...
      ! ... current partition at current level
      faces_c(:,:) = 0
      i = 0
      do s = 1, grid % n_faces
        c1 = grid % faces_c(1, s)
        c2 = grid % faces_c(2, s)

        if(c2 > 0) then
          if(grid % level(lev+1) % cell(c1) .eq. c_lev .and.  &
             grid % level(lev+1) % cell(c2) .eq. c_lev) then
            i = i + 1
            faces_c(1,i) = new_c(c1)
            faces_c(2,i) = new_c(c2)
          end if
        end if
      end do
      n_faces = i

      ! Form cell to cell connectivity for partition and level
      cells_n_cells(:) = 0
      cells_c   (:,:) = 0
      do s = 1, n_faces
        nc1 = faces_c(1,s)
        nc2 = faces_c(2,s)

        cells_n_cells(nc1) = cells_n_cells(nc1) + 1
        cells_n_cells(nc2) = cells_n_cells(nc2) + 1

        cells_c(cells_n_cells(nc1), nc1) = nc2
        cells_c(cells_n_cells(nc2), nc2) = nc1
      end do

      ! Fill-up the structures needed to call METIS (row and col)
      row(:) = 0
      row(1) = 0
      do nc = 1, n_cells
        row(nc+1) = row(nc) + cells_n_cells(nc)
      end do

      col(:) = 0
      do nc = 1, n_cells
        do i = 1, cells_n_cells(nc)
          col(row(nc) + i) = cells_c(i, nc) - 1  ! -1, METIS works from 0
        end do
      end do

      imbalance(:)    = 1.001
      cell_weights(:) = 1
      face_weights(:) = 1
      vert_data(:)    = 1
      part_weight(:)  = 1.0 / real(N_MG_PARTS)

      !-----------------------------------------!
      !   Exectute the call to METIS function   !
      !-----------------------------------------!
      metis_options = -1                       ! Initialize all to default
      metis_options(METIS_OPTION_DBGLVL) = 0
      metis_options(METIS_OPTION_CONTIG) = 1

      call METIS_PartGraphRecursive(n_cells,       &  !  1. (in), int
                                    n_constrains,  &  !  2. (in), int
                                    row,           &  !  3. (in), int(:)
                                    col,           &  !  4. (in), int(:)
                                    cell_weights,  &  !  5. (in), int(:)
                                    vert_data,     &  !  6. (in), int(:)
                                    face_weights,  &  !  7. (in), int(:)
                                    N_MG_PARTS,    &  !  8. (in), int(:)
                                    part_weight,   &  !  9. (in), real(:)
                                    imbalance,     &  ! 10. (in), real(:)
                                    metis_options, &  ! 11. (in), int(:)
                                    return_val,    &  ! 12. (out) int(:)
                                    part(:))          ! 13. (out) int(:)

      part(1:n_cells) = part(1:n_cells) + 1  ! +1, METIS works from zero

      !-----------------------------------------------------!
      !   Save the result from the call to METIS function   !
      !-----------------------------------------------------!
      do nc = 1, n_cells
        c = old_c(nc)
        grid % level(lev) % cell(c) = &
         (grid % level(lev+1) % cell(c)-1) * N_MG_PARTS + part(nc)
      end do
    end do
  end do
  print '(a28,i7,a7)', ' # Finest level 1 contains  ', grid % n_cells, ' cells.'

  !-------------------------------------------------!
  !                                                 !
  !                                                 !
  !   Do the necessary book-keeping on all levels   !
  !                                                 !
  !                                                 !
  !-------------------------------------------------!

  !---------------------------------------------!
  !                                             !
  !     Find cells around faces and and ...     !
  !   ... count number of faces at each level   !
  !                                             !
  !---------------------------------------------!
  do lev = 1, grid % n_levels
    grid % level(lev) % face(:) = 0
    i = 0
    do s = 1, grid % n_faces
      c1 = grid % faces_c(1, s)
      c2 = grid % faces_c(2, s)

      if(c2 > 0) then
        c1_lev = grid % level(lev) % cell(c1)
        c2_lev = grid % level(lev) % cell(c2)

        if(c1_lev .ne. c2_lev) then
          i = i + 1
          grid % level(lev) % faces_c(1, i) = min(c1_lev, c2_lev)
          grid % level(lev) % faces_c(2, i) = max(c1_lev, c2_lev)
          grid % level(lev) % face(i) = s  ! store finest cell number
        end if
      end if
    end do
    grid % level(lev) % n_faces = i
  end do

  !-------------------------------!
  !                               !
  !   Compress face information   !
  !                               !
  !-------------------------------!
  do lev = grid % n_levels, 1, -1

    !----------------------------------------------!
    !   Store face information into spare arrays   !
    !----------------------------------------------!
    c1_arr(:) = 0
    c2_arr(:) = 0
    sf_arr(:) = 0  ! finest face numbers
    do s_lev = 1, grid % level(lev) % n_faces
      c1_arr(s_lev) = grid % level(lev) % faces_c(1, s_lev)
      c2_arr(s_lev) = grid % level(lev) % faces_c(2, s_lev)
      sf_arr(s_lev) = grid % level(lev) % face   (   s_lev)
    end do
    grid % level(lev) % face(:) = 0

    !----------------------------------------------!
    !   Sort faces by both indexes and carry ...   !
    !    ... information on finest face around     !
    !----------------------------------------------!
    call Sort_Mod_2_Int_Carry_Int(c1_arr(1:grid % level(lev) % n_faces),  &
                                  c2_arr(1:grid % level(lev) % n_faces),  &
                                  sf_arr(1:grid % level(lev) % n_faces))

    !---------------------------------------!
    !   Select faces by both cell indices   !
    !---------------------------------------!
    i     = 1
    val_1 = c1_arr(i)
    val_2 = c2_arr(i)
    grid % level(lev) % faces_c(1, i) = val_1
    grid % level(lev) % faces_c(2, i) = val_2
    grid % level(lev) % face( sf_arr(i) ) = i

    do s_lev = 2, grid % level(lev) % n_faces
      if(c1_arr(s_lev) .ne. val_1 .or.  &
         c2_arr(s_lev) .ne. val_2) then
        i = i + 1
        grid % level(lev) % faces_c(1, i) = c1_arr(s_lev)
        grid % level(lev) % faces_c(2, i) = c2_arr(s_lev)
        val_1 = c1_arr(s_lev)
        val_2 = c2_arr(s_lev)
      end if
      grid % level(lev) % face( sf_arr(s_lev) ) = i
    end do
    grid % level(lev) % n_faces = i
    print '(a16,i2,a10,i7,a7)', ' # Coarse level ',           &
                                lev,                          &
                                ' contains ',                 &
                                grid % level(lev) % n_faces,  &
                                ' faces.'
  end do

  !-----------------------------------------!
  !                                         !
  !   Count number of cells at each level   !
  !                                         !
  !-----------------------------------------!
  grid % level(1) % n_cells = grid % n_cells  ! level 0 is the non-coarsen one
  do lev = 2, grid % n_levels
    grid % level(lev) % n_cells = maxval(grid % level(lev) % cell(:))
  end do

  !-------------------------------------!
  !                                     !
  !                                     !
  !   Check sanity of the grid levels   !
  !                                     !
  !                                     !
  !-------------------------------------!

  !--------------------!
  !                    !
  !   Sanity check 1   !
  !                    !
  !--------------------!
  i = 0
  do lev = 1, grid % n_levels
    i = max(i, grid % level(lev) % n_cells)
  end do
  allocate(cell_mapping(MAX_MG_LEVELS, i)); cell_mapping = 0

  do lev = 1, grid % n_levels - 1
    n_cells = maxval(grid % level(lev) % cell(:))
    print '(a,i2,a,i2)', ' # Checking levels', lev, ' and', lev+1

    ! Browse through parts of this level
    do c_lev = 1, n_cells
      do c = 1, grid % n_cells
        if(grid % level(lev) % cell(c) == c_lev) then
          if(cell_mapping(lev, c_lev) .eq. 0) then
            cell_mapping(lev, c_lev) = grid % level(lev+1) % cell(c)
          else
            if(cell_mapping(lev, c_lev) .ne. grid % level(lev+1) % cell(c)) then
              print *, '# Mapping failed at level ', lev
              print *, '# Stopping the program!   '
              stop
            end if
          end if
        end if
      end do
    end do

  end do  ! lev

  !--------------------!
  !                    !
  !   Sanity check 2   !
  !                    !
  !--------------------!
  do lev = 1, grid % n_levels
    do s = 1, grid % n_faces
      c1 = grid % faces_c(1, s)
      c2 = grid % faces_c(2, s)

      if(c2 > 0) then
        c1_lev = grid % level(lev) % cell(c1)
        c2_lev = grid % level(lev) % cell(c2)
        s_lev  = grid % level(lev) % face(s)

        if(s_lev > 0) then
          if(grid % level(lev) % faces_c(1,s_lev) .ne.  &
             min(c1_lev, c2_lev) .or.                   &
             grid % level(lev) % faces_c(2,s_lev) .ne.  &
             max(c1_lev, c2_lev)) then
            print *, '# Cell-face mapping failed at level ', lev
            print *, '# Stopping the program!   '
            stop
          end if
        end if
      end if

    end do
  end do

  !------------------------------------------------!
  !                                                !
  !                                                !
  !   Compute cell coordinates at coarser levels   !
  !                                                !
  !                                                !
  !------------------------------------------------!
  do lev = 1, grid % n_levels

    grid % level(lev) % xc(:) = 0
    grid % level(lev) % yc(:) = 0
    grid % level(lev) % zc(:) = 0
    grid % level(lev) % n_finest_cells(:) = 0

    do c = 1, grid % n_cells

      c_lev = grid % level(lev) % cell(c)
      grid % level(lev) % xc(c_lev) = grid % level(lev) % xc(c_lev)  &
                                    + grid % xc(c)
      grid % level(lev) % yc(c_lev) = grid % level(lev) % yc(c_lev)  &
                                    + grid % yc(c)
      grid % level(lev) % zc(c_lev) = grid % level(lev) % zc(c_lev)  &
                                    + grid % zc(c)

      grid % level(lev) % n_finest_cells(c_lev) =    &
      grid % level(lev) % n_finest_cells(c_lev) + 1
    end do

    do c_lev = 1, grid % level(lev) % n_cells
      grid % level(lev) % xc(c_lev) = grid % level(lev) % xc(c_lev)  &
                                    / grid % level(lev) % n_finest_cells(c_lev)
      grid % level(lev) % yc(c_lev) = grid % level(lev) % yc(c_lev)  &
                                    / grid % level(lev) % n_finest_cells(c_lev)
      grid % level(lev) % zc(c_lev) = grid % level(lev) % zc(c_lev)  &
                                    / grid % level(lev) % n_finest_cells(c_lev)
    end do
  end do

  deallocate(col)
  deallocate(row)
  deallocate(part_weight)
  deallocate(vert_data)
  deallocate(face_weights)
  deallocate(cell_weights)
  deallocate(imbalance)
  deallocate(old_c)
  deallocate(new_c)

  end subroutine
