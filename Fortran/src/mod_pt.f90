!==============================================================================
!> \file mod_pt.f90
!> Module for the param tree input-data handling library.
!>
!> \author Ralf Schneider
!> \date 20.08.2021
!>

!===============================================================================
!> The param tree input-data handling library.
!>
!> The module provides functionalities to store and read back data from the
!> provided paramter tree pt which is also provided by this module.
!>
!> \author Ralf Schneider
!> \date 20.08.2021
!>
Module param_tree

  Use ISO_FORTRAN_ENV
  
  use strings
  
  Use pt_constants
  Use pt_types

  Implicit None

  !============================================================================
  !== Private routines
  
  
  !============================================================================
  !== Interfaces
  !> Getter functions to retrieve values from pt to local variables
  interface pt_get
     module procedure pt_get_1d_i8
     module procedure pt_get_scalar_i8

     module procedure pt_get_2d_r8
     
     module procedure pt_get_1d_char
     module procedure pt_get_scalar_char

     module procedure pt_get_scalar_l
  end interface pt_get

  !! -----------------------------------
  !> The parameter tree
  Type(pt_branch), Private, Save :: pt

  !! -----------------------------------
  !> Monitor- / Logfile unit
  Integer                       :: pt_umon  = OUTPUT_UNIT
  
Contains

  !############################################################################
  !> \name param tree public getter subroutines
  !> @{
  !> Module procedures for data retrieval from pt.
  
  !! ===========================================================================
  !> Subroutine to rerieve a scalar integer 8 value from pt
  Subroutine pt_get_scalar_i8(p_name,arr,success)

    character(len=*)               , intent(in)   :: p_name
    integer(kind=pt_ik)            , intent(out)  :: arr

    Logical, optional, intent(out)                  :: success
    Logical                                         :: loc_success

    
    call get_scalar_i8(p_name,pt,arr,loc_success)

    if (.not.present(success)) then
       if (.not. loc_success) write(pt_umon,PTF_W_A)trim(p_name)//" was not found!"
    else
       success = loc_success
    End if

  End Subroutine pt_get_scalar_i8

  !! ===========================================================================
  !> Subroutine to rerieve a 1D integer 8 value from pt
  Subroutine pt_get_1d_i8(p_name,arr,success)

    character(len=*)               , intent(in)   :: p_name
    integer(kind=pt_ik),allocatable, Dimension(:) :: arr

    Logical, optional, intent(out)                  :: success
    Logical                                         :: loc_success
    
    call get_1d_i8(p_name,pt,arr,loc_success)

    if (.not.present(success)) then
       if (.not. loc_success) write(pt_umon,PTF_W_A)trim(p_name)//" was not found!"
    else
       success = loc_success
    End if

  End Subroutine pt_get_1d_i8
  !! ===========================================================================
  !> Subroutine to rerieve a 2D real 8 value from pt
  Subroutine pt_get_2d_r8(p_name,arr,success)

    character(len=*)               , intent(in)   :: p_name
    Real(kind=pt_rk),allocatable, Dimension(:,:)  :: arr

    Logical, optional, intent(out)                  :: success
    Logical                                         :: loc_success
    
    call get_2d_r8(p_name,pt,arr,loc_success)

    if (.not.present(success)) then
       if (.not. loc_success) write(pt_umon,PTF_W_A)trim(p_name)//" was not found!"
    else
       success = loc_success
    End if

  End Subroutine pt_get_2d_r8

  !! ===========================================================================
  !> Subroutine to rerieve a scalar character value from pt
  Subroutine pt_get_scalar_char(p_name,arr,success)

    character(len=*)               , intent(in)     :: p_name
    character(len=:),allocatable   , intent(inout)  :: arr

    Logical, optional, intent(out)                  :: success
    Logical                                         :: loc_success
    
    call get_scalar_char(p_name,pt,arr,loc_success)

    if (.not.present(success)) then
       if (.not. loc_success) write(pt_umon,PTF_W_A)trim(p_name)//" was not found!"
    else
       success = loc_success
    End if
    
  End Subroutine pt_get_scalar_char

  !! ===========================================================================
  !> Subroutine to rerieve a 1D character value from pt
  Subroutine pt_get_1d_char(p_name,char_arr,success)

    character(len=*)            , intent(in)   :: p_name
    character(len=:),allocatable, Dimension(:) :: char_arr

    Logical, optional, intent(out)                  :: success
    Logical                                         :: loc_success
    
    call get_1d_char(p_name,pt,char_arr,loc_success)

    if (.not.present(success)) then
       if (.not. loc_success) write(pt_umon,PTF_W_A)trim(p_name)//" was not found!"
    else
       success = loc_success
    End if

  End Subroutine pt_get_1d_char

  !! ===========================================================================
  !> Subroutine to rerieve a scalar logical value from pt
  Subroutine pt_get_scalar_l(p_name,arr,success)
    
    character(len=*)               , intent(in)     :: p_name
    logical                        , intent(inout)  :: arr

    Logical, optional, intent(out)                  :: success
    Logical                                         :: loc_success
    
    call get_scalar_l(p_name,pt,arr,loc_success)

    if (.not.present(success)) then
       if (.not. loc_success) write(pt_umon,PTF_W_A)trim(p_name)//" was not found!"
    else
       success = loc_success
    End if
    
  End Subroutine pt_get_scalar_l
  
  !> @}

  !============================================================================
  !> \name param tree private getter subroutines
  !> @{
  !> Module procedures for data retrieval from pt. Since they are recursive
  !> they have to have a branch as input parameter
  
  !! ===========================================================================
  !> Subroutine to rerieve a scalar integer 8 value from a branch
  Recursive subroutine get_scalar_i8(p_name,branch,arr,success)

    character(len=*)   , intent(in)  :: p_name
    Type(pt_branch)    , intent(in)  :: branch
    integer(kind=pt_ik), intent(out) :: arr
    Logical            , intent(inout)              :: success

    integer                          :: ii, jj, c_len

    do ii = 1, branch%no_branches
       call  get_scalar_i8(p_name,branch%branches(ii),arr,success)
    End do

    do ii = 1, branch%no_leaves

       if (p_name == trim(branch%leaves(ii)%name)) then

          arr = branch%leaves(ii)%i8(1)
          success = .TRUE.
         
       end if

    End do

  End subroutine get_scalar_i8

  !! ===========================================================================
  !> Subroutine to rerieve a 1D integer 8 value from a branch
  Recursive subroutine get_1d_i8(p_name,branch,arr,success)

    character(len=*)   , intent(in)                            :: p_name
    Type(pt_branch)    , intent(in)                            :: branch
    integer(kind=pt_ik), Allocatable, Dimension(:),intent(out) :: arr
    Logical            , intent(inout)              :: success

    integer                                    :: ii, jj, c_len

    do ii = 1, branch%no_branches
       call  get_1d_i8(p_name,branch%branches(ii),arr,success)
    End do

    do ii = 1, branch%no_leaves

       if (p_name == trim(branch%leaves(ii)%name)) then

          arr = branch%leaves(ii)%i8
          success = .TRUE.
          
       end if

    End do

  End subroutine get_1d_i8
  
  !! ===========================================================================
  !> Subroutine to rerieve a 1D integer 8 value from a branch
  Recursive subroutine get_2d_r8(p_name,branch,arr,success)

    character(len=*)   , intent(in)                            :: p_name
    Type(pt_branch)    , intent(in)                            :: branch
    Real(kind=pt_rk), Allocatable, Dimension(:,:),intent(out)  :: arr
    Logical            , intent(inout)                         :: success

    integer                                    :: ii, jj, c_len

    do ii = 1, branch%no_branches
       call  get_2d_r8(p_name,branch%branches(ii),arr,success)
    End do

    do ii = 1, branch%no_leaves

       if (p_name == trim(branch%leaves(ii)%name)) then

          arr = reshape(&
               branch%leaves(ii)%r8,&
               [branch%leaves(ii)%dat_no(1),branch%leaves(ii)%dat_no(2)]&
               )
          success = .TRUE.
          
       end if

    End do

  End subroutine get_2d_r8
  
  !! ===========================================================================
  !> Subroutine to rerieve a scalar character value from a branch
  Recursive subroutine get_scalar_char(p_name,branch,arr,success)

    character(len=*)   , intent(in)  :: p_name
    Type(pt_branch)    , intent(in)  :: branch
    character(len=:)   , intent(inout), allocatable :: arr
    Logical            , intent(inout)              :: success
    
    integer                          :: ii, jj, c_len

    success = .FALSE.
    
    do ii = 1, branch%no_branches
       call  get_scalar_char(p_name,branch%branches(ii),arr,success)
    End do

    do ii = 1, branch%no_leaves

       if (p_name == trim(branch%leaves(ii)%name)) then

          arr = trim(branch%leaves(ii)%ch(1))
          success = .TRUE.
          
       end if

    End do

  End subroutine get_scalar_char

  !! ===========================================================================
  !> Subroutine to rerieve a 1D character value
  Recursive subroutine get_1d_char(p_name,branch,char_arr,success)

    character(len=*)     , intent(in)                      :: p_name
    Type(pt_branch)      , intent(in)                      :: branch
    character(len=:),allocatable, Dimension(:),intent(out) :: char_arr
    Logical              , intent(inout)                   :: success

    integer                                    :: ii, jj, c_len

    do ii = 1, branch%no_branches
       call  get_1d_char(p_name,branch%branches(ii),char_arr,success)
    End do

    do ii = 1, branch%no_leaves

       if (p_name == trim(branch%leaves(ii)%name)) then

          c_len = len_trim(branch%leaves(ii)%ch(1))

          Allocate(char_arr(branch%leaves(ii)%dat_no(1)),&
               mold=branch%leaves(ii)%ch(1)(1:c_len))

          Do jj = 1, branch%leaves(ii)%dat_no(1)
             char_arr(jj) = branch%leaves(ii)%ch(jj)(1:c_len)
          End Do

          success = .TRUE.
          
       end if

    End do

  End subroutine get_1d_char

  !! ===========================================================================
  !> Subroutine to rerieve a scalar logical value from a branch
  Recursive subroutine get_scalar_l(p_name,branch,arr,success)

    character(len=*)   , intent(in)    :: p_name
    Type(pt_branch)    , intent(in)    :: branch
    Logical            , intent(inout) :: arr
    Logical            , intent(inout) :: success
    
    integer                            :: ii, jj, c_len

    success = .FALSE.
    
    do ii = 1, branch%no_branches
       call  get_scalar_l(p_name,branch%branches(ii),arr,success)
    End do

    do ii = 1, branch%no_leaves

       if (p_name == trim(branch%leaves(ii)%name)) then

          arr = branch%leaves(ii)%l(1)
          success = .TRUE.
          
       end if

    End do

  End subroutine get_scalar_l
  !> @}
  
  !! ===========================================================================
  !> Subroutine which prints out the param tree structure
  Subroutine write_param_tree(unit_lf)

    Integer         , Intent(in)            :: unit_lf
   
    write(pt_umon,'(80("#"))')
    call log_pt_branch(branch=pt,unit_lf=unit_lf,data=.TRUE.)
    write(pt_umon,'(80("#"))')
    
  End Subroutine write_param_tree

  !! ===========================================================================
  !> Subroutine which prints out a pt_branch structure
  Recursive Subroutine log_pt_branch(branch, unit_lf, fmt_str_in, data)

    Type(pt_branch), intent(in)             :: branch
    Integer         , Intent(in)            :: unit_lf
    Character(len=*), Intent(In) , optional :: fmt_str_in
    Logical         , Intent(In) , optional :: data

    Integer                                 :: ii, lt_desc, len_fmt_str
    Integer                                 :: spacer

    Character(Len=pt_mcl)                   :: b_sep

    Character(len=pt_mcl)                   :: fmt_str   = ''

    Logical                                 :: loc_data, loc_commands
    
    !---------------------------------------------------------------------------
    spacer=Len_Trim(branch%desc)+23

    if (present(fmt_str_in)) then
       fmt_str     = fmt_str_in
       len_fmt_str = Len(fmt_str_in)
    Else
       fmt_str     = ' '
       len_fmt_str = 1
    end if
    
    If (present(data)) Then
       loc_data = data
    Else
       loc_data = .FALSE.
    End If
 
    Write(unit_lf, "('"//fmt_str(1:len_fmt_str-1)//"|')")

    If ( Len_Trim(branch%desc) < 1 ) then
       lt_desc = 1 
    Else
       lt_desc = Len_Trim(branch%desc)
    end If
    
    Write(b_sep,'(A,I0,A)')"('"//fmt_str(1:len_fmt_str-1)//"|   +----------',",LT_desc,"('-'),'-+')"
    
    write(pt_umon, b_sep)
    Write(unit_lf, "('"//fmt_str(1:len_fmt_str-1)//"+---|',A,A,A)") ' Branch : ',Trim(branch%desc),' |'

    Write(b_sep,'(A,I0,A)')"('"//fmt_str(1:len_fmt_str)//"   +----------',",LT_desc,"('-'),'-+')"
    Write(unit_lf, b_sep)

    Write(unit_lf, "('"//fmt_str(1:len_fmt_str)//"   |')")
 
    Write(unit_lf, "('"//fmt_str(1:len_fmt_str)//"   +-- No of branches = ',I0)")branch%no_branches
    Write(unit_lf, "('"//fmt_str(1:len_fmt_str)//"   +-- No of leaves   = ',I0)")branch%no_leaves
    
    do ii = 1, branch%no_branches
       If ((ii < branch%no_branches) .Or. (branch%no_leaves > 0)) Then
          Call log_pt_branch(branch%branches(ii) ,unit_lf, fmt_str(1:len_fmt_str)//"   |", loc_data)
       Else
          Call log_pt_branch(branch%branches(ii) ,unit_lf, fmt_str(1:len_fmt_str)//"    ", loc_data)
       End If
    end do

    do ii = 1, branch%no_leaves
       If (ii < branch%no_leaves) Then
          Call log_pt_leaf(branch%leaves(ii), unit_lf, &
                           fmt_str(1:len_fmt_str)//"   |", data, branch)
       Else
          Call log_pt_leaf(branch%leaves(ii), unit_lf, &
                           fmt_str(1:len_fmt_str)//"    ", data, branch) 
       End If
    end do

  End Subroutine log_pt_branch

  !! ===========================================================================
  !> Subroutine which prints out a pt_leaf structure
  Subroutine log_pt_leaf(leaf, unit_lf, fmt_str_in, data, parent)

    Type(pt_leaf)   , intent(in)            :: leaf
    Integer         , Intent(in)            :: unit_lf
    Character(len=*), Intent(In) , optional :: fmt_str_in
    Logical         , Intent(In) , optional :: data
    Type(pt_Branch) , Intent(in) , optional :: parent 

    Character(Len=pt_mcl)           :: b_sep, fmt_str
    Integer                         :: lt_desc, len_fmt_str

    Logical                         :: loc_data

    !---------------------------------------------------------------------------
    
    if (present(fmt_str_in)) then
       fmt_str     = fmt_str_in
       len_fmt_str = Len(fmt_str_in)
    Else
       fmt_str     = ' '
       len_fmt_str = 1
    end if

    If (present(data)) Then
       loc_data = data
    Else
       loc_data = .FALSE.
    End If
    
    Write(unit_lf, "('"//fmt_str(1:Len_fmt_str-1)//"|')")

    If ( Len_Trim(leaf%name) < 1 ) then
       lt_desc = 1 
    Else
       lt_desc = Len_Trim(leaf%name)
    end If

    Write(b_sep,'(A,I0,A)')"('"//fmt_str(1:Len_fmt_str-1)//"|   +--------',",LT_desc,"('-'),'-+')"
    Write(unit_lf, b_sep)
    Write(unit_lf, "('"//fmt_str(1:len_fmt_str-1)//"+---| ',A,A)")'Leaf : ',Trim(leaf%name)//' |'
    Write(b_sep,'(A,I0,A)')"('"//fmt_str(1:len_fmt_str)//"   +--------',",LT_desc,"('-'),'-+')"
    Write(unit_lf, b_sep)

    Write(unit_lf, "('"//fmt_str(1:len_fmt_str)//"   |')")
    Write(unit_lf, "('"//fmt_str(1:len_fmt_str)//"   +-- Type of data : ',A)")leaf%dat_ty
    Write(unit_lf, "('"//fmt_str(1:len_fmt_str)//"   +-- Dimension    : ',I0)")leaf%dat_dim
    Write(unit_lf, "('"//fmt_str(1:len_fmt_str)//"   +-- No. of data  : ',*(I0,1X))")leaf%dat_no 

    If (loc_data) then
       Call log_pt_Leaf_data(unit_lf, leaf, fmt_str(1:len_fmt_str))
    End If

  End Subroutine log_pt_leaf

  !! ===========================================================================
  !> This subroutine prints out data contained in a pt_Leaf structure.
  Subroutine Log_pt_Leaf_data(un_lf, leaf, fmt_str)

    Integer           , Intent(in) :: un_lf
    Type(pt_Leaf)     , Intent(In) :: leaf
    Character(Len=*)  , Intent(In) :: fmt_str
    
    Character(Len=pt_mcl)          :: fmt_space

    Integer :: ii, pos, n_data
    
    Write(un_lf, "('"//fmt_str//"   |')")
    Write(un_lf, "('"//fmt_str//"   +',170('-'),('+'))")
    Write(un_lf, "('"//fmt_str//"   |',' Leaf Data ',159(' '),('|'))")

    n_data = 1
    
    Do ii = 1, size(leaf%dat_no)
       n_data = n_data * leaf%dat_no(ii)
    End Do
       
    !***********************************************************
    !** n_data in [0,30] ***************************************
    If (n_data <= 30) then

       Write(un_lf, "('"//fmt_str//"   |')",ADVANCE='NO')

       pos = 1
       
       Select Case (leaf%dat_ty)

       Case ("I","R","L")
          
          Do ii = 1, n_data

             Select Case (leaf%dat_ty)
             Case ("I")          
                Write(un_lf, "(I16,' ')", ADVANCE='NO')leaf%i8(ii)
             Case ("R")
                Write(un_lf, "(I16,' ')", ADVANCE='NO')leaf%r8(ii)
             Case ("L")
                Write(un_lf, "(L16,' ')", ADVANCE='NO')leaf%l(ii)
             End Select
             
             If ( mod(pos,10) == 0) then
                Write(un_lf, "('|')")
                Write(un_lf, "('"//fmt_str//"   |')",ADVANCE='NO')
                pos = 0
             End If
             pos = pos + 1
             
          End Do

          Do ii = 1, 10-mod(n_data,10)
             Write(un_lf, "(17(' '))", ADVANCE='NO')
          End Do
          Write(un_lf, "('|')")
          
       Case ("C")

          Do ii = 1, n_data

             pos = pos + len_trim(leaf%ch(ii))+2
             If ( pos >= 169 ) then
                Write(un_lf, "('|')")
                Write(un_lf, "('"//fmt_str//"   |')",ADVANCE='NO')
                pos = 1
             End If
 
             Write(un_lf, "('|',A,'|')", ADVANCE='NO')trim(leaf%ch(ii))
                         
          End Do

          Write(fmt_space, "(A,I0,A)")"(",170-pos+1,"(' '))"
          Write(un_lf,fmt_space, ADVANCE='NO')
          Write(un_lf, "('|')")

       End Select
          
    End If

    Write(un_lf, "('"//fmt_str//"   +',170('-'),('+'))")

  End Subroutine Log_pt_Leaf_data
  !! ===========================================================================
  !> Subroutine which reads all parameters from a file
  Subroutine read_param_file(name)

    Character(len=*),Intent(in)      :: name
    Integer                          :: un, io_stat
    Integer                          :: n_lines, n_params, n_files
    integer                          :: line_len, dat_dim
    integer                          :: ii, nn, kk, pos, nn_fields, n_elem, elems_read

    Character(Len=pt_mcl), Allocatable, Dimension(:)  :: lines

    character(len=:),Dimension(:),allocatable :: str_arr

    Character(Len=pt_mcl) :: keyword
    Character             :: dat_ty

    Type(pt_branch) :: pt_tmp

    !! -------------------------------------------------------------------------

    Open(newunit=un,    file=Trim(name), status="old", &
         action="read", iostat=io_stat )

    If (io_stat /= 0) Then
       write(pt_umon,PTF_file_missing)Trim(name)
       Stop
    End If

    write(pt_umon,PTF_sep)
    write(pt_umon,PTF_M_A)"Reading file:"//trim(name)
   
    n_lines =  get_lines_in_file(un)

    write(pt_umon,PTF_M_AI0)"Number of lines in file:",n_lines

    Rewind(un)

    Allocate(lines(n_lines))

    Read(un,'(A)',iostat=io_stat)lines

    Close(un)

    !! Add new parameter branch to parameter tree --------------------
    if (allocated(pt%branches)) then
       nn = size(pt%branches)
       allocate(pt_tmp%branches(nn))
       pt_tmp%branches = pt%branches
       deallocate(pt%branches)
       allocate(pt%branches(nn+1))
       pt%branches(1:nn) = pt_tmp%branches
       n_files = nn + 1
    else
       allocate(pt%branches(1))
       n_files = 1
       pt%desc = "Global Param Tree"
    End if

    pt%no_branches = n_files

    !! Count parameters ----------------------------------------------
    ii = 1
    n_params = 0
    Do while (ii <= n_lines)
       if (lines(ii)(1:1) == "#") n_params = n_params + 1
       ii = ii + 1 
    End Do

    write(pt_umon,PTF_M_AI0)"Number of parameters in file:",n_params
    write(pt_umon,*)
    
    !! Read parameters ----------------------------------------------
    Allocate(pt%branches(n_files)%leaves(n_params))
    pt%branches(n_files)%no_leaves = n_params
    pt%branches(n_files)%desc = trim(name)
    
    ii = 1
    nn = 0
    Line_Loop: Do while (ii <= n_lines)

       line_len = len_trim(lines(ii))

       !! --------------------------------------------------
       !! If a keyword was found ---------------------------
       if (lines(ii)(1:1) == "#") then

          !! ---------------------------------------------------------
          !! Increase param counter ----------------------------------
          nn = nn + 1

          !! ---------------------------------------------------------
          !! Get Keyword ---------------------------------------------
          !! A keyword line has to have the following layout
          !! #<keyword> , <data_type> , #elems dim1, #elems dim2, ...

          !! Get positions of field seperator --------------
          str_arr = strtok(lines(ii),fsep)
          !! Calc number of fields in keyword line ---------
          nn_fields = size(str_arr)

          Select Case (nn_fields)
          case(0)
             write(pt_umon,PTF_SEP)
             write(pt_umon,PTF_E_A)"Something bad and unexpected happened!"
             write(pt_umon,PTF_E_A)"No fields were found in keyword line !"
             write(pt_umon,PTF_E_AI0)"Param no:",nn
             write(pt_umon,PTF_E_AI0)"Line no:" ,ii
             write(pt_umon,PTF_E_A)"Line image:"//lines(ii)
             write(pt_umon,PTF_E_STOP)
             stop

          Case(1)
             write(pt_umon,PTF_SEP)
             write(pt_umon,PTF_W_A)"Only found one field in keyword line."
             write(pt_umon,PTF_W_AI0)"Param no:",nn
             write(pt_umon,PTF_W_AI0)"Line no:" ,ii
             write(pt_umon,PTF_W_A)"Line image:"//trim(lines(ii))
             write(pt_umon,PTF_W_A)"Assuming a scalar string parameter."

             keyword = str_arr(1)
             dat_ty  = "c"
             dat_dim = 1

             Allocate(pt%branches(n_files)%leaves(nn)%dat_no(1))
             pt%branches(n_files)%leaves(nn)%dat_no = 1

          Case(2)
             write(pt_umon,PTF_SEP)
             write(pt_umon,PTF_W_A)"Only found two fields in keyword line."
             write(pt_umon,PTF_W_AI0)"Param no:",nn
             write(pt_umon,PTF_W_AI0)"Line no:" ,ii
             write(pt_umon,PTF_W_A)"Line image:"//trim(lines(ii))
             write(pt_umon,PTF_W_A)"Assuming a scalar parameter."

             keyword = str_arr(1)
             dat_ty  = ToUpperCase(str_arr(2))
             dat_dim = 1

             Allocate(pt%branches(n_files)%leaves(nn)%dat_no(1))
             pt%branches(n_files)%leaves(nn)%dat_no = 1

          Case default

             keyword = str_arr(1)
             dat_ty  = ToUpperCase(str_arr(2))
             dat_dim = nn_fields-2

             Allocate(pt%branches(n_files)%leaves(nn)%dat_no(dat_dim))
             Do kk = 3, nn_fields
                Read(str_arr(kk),*,iostat=io_stat)pt%branches(n_files)%leaves(nn)%dat_no(kk-2)

                if (io_stat /= 0) then
                   write(pt_umon,PTF_SEP)
                   write(pt_umon,PTF_W_A)"Reading field with number of parameters failed."
                   write(pt_umon,PTF_W_AI0)"Field no:",kk
                   write(pt_umon,PTF_W_AI0)"Param no:",nn
                   write(pt_umon,PTF_W_AI0)"Line no:" ,ii
                   write(pt_umon,PTF_W_A)"Line image:"//trim(lines(ii))
                   write(pt_umon,PTF_W_A)"Skipping read."

                   !! Save elements of tree structure from shortened variables ----------
                   pt%branches(n_files)%leaves(nn)%name    = keyword
                   pt%branches(n_files)%leaves(nn)%dat_ty  = dat_ty
                   pt%branches(n_files)%leaves(nn)%dat_dim = dat_dim
                   pt%branches(n_files)%leaves(nn)%dat_no(kk-2:nn_fields-2) = -1
                   
                   ii = ii + 1
                   cycle Line_Loop
                   
                End if
             End Do

          End Select

          !! Save elements of tree structure from shortened variables ----------
          pt%branches(n_files)%leaves(nn)%name    = keyword
          pt%branches(n_files)%leaves(nn)%dat_ty  = dat_ty
          pt%branches(n_files)%leaves(nn)%dat_dim = dat_dim

          !! -------------------------------------------------------------------
          !! Get Values --------------------------------------------------------

          !! Determine number of elements in linear field ------------
          n_elem = 1
          do kk = 1, dat_dim
             n_elem = n_elem * pt%branches(n_files)%leaves(nn)%dat_no(kk)
          End do

          !! Allocate datafield --------------------------------------
          Select Case(dat_ty)

          Case ("I")
             Allocate(pt%branches(n_files)%leaves(nn)%i8(n_elem))

          Case ("R")
             Allocate(pt%branches(n_files)%leaves(nn)%r8(n_elem))

          Case ("C")
             Allocate(pt%branches(n_files)%leaves(nn)%ch(n_elem))

          Case ("L")
             Allocate(pt%branches(n_files)%leaves(nn)%l(n_elem))

          Case default

             write(pt_umon,PTF_SEP)
             write(pt_umon,PTF_W_A)"Don't know how to handle dat_ty"
             write(pt_umon,PTF_W_A)trim(dat_ty)
             write(pt_umon,PTF_W_AI0)"Param no:",nn
             write(pt_umon,PTF_W_AI0)"Line no:" ,ii
             write(pt_umon,PTF_W_A)"Line image:"//trim(lines(ii))
             write(pt_umon,PTF_W_A)"Allocating no data elements."

             ii = ii + 1
             cycle Line_Loop

          End Select

          elems_read = 0

          Do while (elems_read < n_elem)

             !! Goto next line ------------
             ii = ii + 1

             !! Get positions of field seperator -----------
             str_arr = strtok(lines(ii),fsep)
             !! Calc number of fields in keyword line ------
             nn_fields = size(str_arr)

             if ( elems_read + nn_fields > n_elem ) then

                write(pt_umon,PTF_SEP)
                write(pt_umon,PTF_W_A)"Number of elements given is apparently larger than"
                write(pt_umon,PTF_W_A)"the number of elemets specified in keyword line."
                write(pt_umon,PTF_W_AI0)"# elems to read:",elems_read + nn_fields
                write(pt_umon,PTF_W_AI0)"# elems in keyword line:",pt%branches(n_files)%leaves(nn)%dat_no
                write(pt_umon,PTF_W_AI0)"Param no:",nn
                write(pt_umon,PTF_W_AI0)"Line no:" ,ii
                write(pt_umon,PTF_W_A)"Line image:"//trim(lines(ii))

                nn_fields = n_elem  - elems_read

             End if

             !! Read data elements -------------------------
             Select Case(dat_ty)

             Case ("I")
                Do kk = 1, nn_fields
                   Read(str_arr(kk),*,iostat=io_stat)pt%branches(n_files)%leaves(nn)%i8(elems_read+kk)
                   if (io_stat /= 0) exit
                End Do

             Case ("R")
                Do kk = 1, nn_fields
                   Read(str_arr(kk),*,iostat=io_stat)pt%branches(n_files)%leaves(nn)%r8(elems_read+kk)
                   if (io_stat /= 0) exit
                End Do

             Case ("C")
                Do kk = 1, nn_fields
                   Read(str_arr(kk),*,iostat=io_stat)pt%branches(n_files)%leaves(nn)%ch(elems_read+kk)
                   if (io_stat /= 0) exit
                End Do

             Case ("L")
                Do kk = 1, nn_fields
                   Read(str_arr(kk),*,iostat=io_stat)pt%branches(n_files)%leaves(nn)%l(elems_read+kk)
                   if (io_stat /= 0) exit
                End Do

             End Select

             if (io_stat /= 0) then
                write(pt_umon,PTF_SEP)
                write(pt_umon,PTF_W_A)"Reading of data elements failed"
                write(pt_umon,PTF_W_AI0)"Param no:",nn
                write(pt_umon,PTF_W_AI0)"Line no:" ,ii
                write(pt_umon,PTF_W_A)"Line image:"//trim(lines(ii))
                write(pt_umon,PTF_W_A)"Skipping read in of further data."

                ii = ii + 1
                cycle Line_Loop
             end if

             elems_read = elems_read + nn_fields

          End Do
       End if

       ii = ii + 1 

    End Do Line_Loop

    write(pt_umon,*)
    
  End Subroutine read_param_file

End Module param_tree