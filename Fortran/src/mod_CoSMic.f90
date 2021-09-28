!###############################################################################
!###############################################################################
!#      ___      __         _      
!#     / __\___ / _\  /\/\ (_) ___ 
!#    / /  / _ \\ \  /    \| |/ __|
!#   / /__| (_) |\ \/ /\/\ \ | (__ 
!#   \____/\___/\__/\/    \/_|\___|
!#
!#  COVID-19 Spatial Microsimulation  ---  For Germany  ########################
!###############################################################################
!#
!# Authors:      Qifeng Pan
!#               Ralf Schneider
!#               Christian Dudel
!#               Matthias Rosenbaum-Feldbruegge
!#               Sebastian Kluesener
!#
!# Contact:      ralf.schneider@hlrs.de
!#               qifeng.pan@hlrs.de
!#
!#==============================================================================
!#
!# Copyright (C) 2021 High Performance Computing Center Stuttgart (HLRS),
!#                    Federal Institute for Population Research (BIB),
!#                    The Max Planck Institute for Demographic Research (MPIDR)
!# 
!# This program is free software: you can redistribute it and/or modify
!# it under the terms of the GNU General Public License as published by
!# the Free Software Foundation, either version 3 of the License, or
!# (at your option) any later version.
!# 
!# This program is distributed in the hope that it will be useful,
!# but WITHOUT ANY WARRANTY; without even the implied warranty of
!# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
!# GNU General Public License for more details.
!# 
!# You should have received a copy of the GNU General Public License
!# along with this program.  If not, see <http://www.gnu.org/licenses/>.
!#
!###############################################################################
!
! Module containing the CoSMic model loop
!
!###############################################################################
Module kernel

  use timer

  use param_tree

  use precision
  Use global_constants
  use global_types
  use global_vars
  
  Use list_variable
  Use support_fun
  use qsort_c_module
  
  Implicit None

  Type icu_risk_lists ! in order to have a similar structure to R
     Character*2,Allocatable         :: age(:)
     Integer,Allocatable             :: agei(:)
     Character*1,Allocatable         :: sex(:)
     Real,Allocatable                :: risk(:)
     Integer,Allocatable             :: dur(:)
  End Type icu_risk_lists

  Type sims
     Integer,Allocatable             :: dist_id(:)
     Integer,Allocatable             :: dist_id_rn(:)
     Character,Allocatable           :: sex(:)
     Character*2,Allocatable         :: age(:)
     Integer,Allocatable             :: agei(:)
     Integer,Allocatable             :: t1(:)
     Integer,Allocatable             :: t2(:)
     Integer,Allocatable             :: d(:)
  End Type sims

  !> states an individual can reach
  Integer, Parameter ::   missing    = -1
  Integer, Parameter ::   healthy    = 0
  Integer, Parameter ::   inf_noncon = 1
  Integer, Parameter ::   inf_contag = 2
  Integer, Parameter ::   ill_contag = 3
  Integer, Parameter ::   ill_ICU    = 4
  Integer, Parameter ::   immune     = 5
  Integer, Parameter ::   dead       = 6

  Integer, Parameter ::   min_state  = -1
  Integer, Parameter ::   max_state  =  6
Contains
  
  Subroutine COVID19_Spatial_Microsimulation_for_Germany( &
       iol, pspace, counties_index &
       )

    !===========================================================================
    ! Declaration
    !===========================================================================

    !Include 'mpif.h'

    Type(static_parameters) :: sp

    Type(pspaces)       :: pspace
    Type(iols)          :: iol
    
    Integer             :: i, j, k, index, temp_int,icounty,county,it_ss,iter,status
    Character*1         :: mod1,mod2
    Integer,Dimension(:):: counties_index
    Logical             :: seed_in_inner_loop,seed_mpi_in_inner_loop
!!!!!-----1.states of the model ------

!!!!!-----2.derive the initial population ------
    Real                :: sam_prop_ps(16)=(/1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1/) ! scaling coeff for population

!!!!!-----3.Set seed infections in population ------
    Integer             :: ini_infected
    Character*5         :: seed_infections
    Integer             :: seed_before

!!!!!-----4. define disease characteristics -----
    Real                :: R0_force
    !?? pspace
    Integer             :: inf_dur,cont_dur,ill_dur,icu_dur
    Real                :: icu_per_day(8)=(/0.0,0.0,0.0,0.0,0.0,0.0,0.0,8.0/)
    Real                :: less_contagious
    Logical             :: immune_stop

!!!!!-----5. define reductions in social contacts -----
    Integer(kind=ik), Allocatable, Dimension(:,:) :: R0change
    Logical             :: R0delay
    Integer             :: R0delay_days
    Character(len=:),Allocatable :: R0delay_type

!!!!!-----7.  Define whether transition probabilities should differ by age and sex
    Character*10        :: control_age_sex
    Character*10        :: seed_before_char,seed_temp
    Character*10,Allocatable :: seed_seq(:),seed_inf_cont_seq(:),seed_inf_ncont_seq(:)
    Character*10,Allocatable :: seed_d_seq(:)
    Integer             :: days

    Integer             :: n_direct,n_directv,n_directl,n_dist
    Integer             :: size_lhc
    Real(kind=rk),Allocatable    :: lhc(:,:)
    Integer(kind=ik)             :: tmp_i8

!!!!!-----8. variables for do loop -------
    Real,Allocatable    :: icu_risk(:),surv_ill(:),surv_icu(:)
    Integer,Allocatable :: temp1(:),temp(:),targert_icu_risk_index(:)

    Integer,Allocatable,Dimension(:) :: temp_s
    
    Character*3,Allocatable :: temp_char_mul(:)
    Character               :: temp_char_sig

    Type(icu_risk_lists)            :: icu_risk_list,surv_ill_list,surv_icu_list

    Type(sims)                      :: sim,tmp
    Integer,Allocatable             :: tmp_dnew(:)
    Integer,Allocatable             :: sim_counties(:),rownumbers(:)

    Type(seeds)                     :: seed_ill,seed_inf_cont,seed_inf_ncont,target_inf
    Integer,Allocatable             :: seed_ill_dur(:),seed_inf_cont_dur(:),seed_inf_ncont_dur(:)
    Integer,Allocatable             :: il_d(:),inf_c_d(:),inf_nc_d(:)
    Integer,Allocatable             :: rownumbers_ill(:),rownumbers_cont(:),rownumbers_ncont(:),rownumbers_dea(:),&
         rownumbers_left(:)
    Integer,Allocatable             :: gettime(:)
    Real,Allocatable                :: getchange(:)
    Integer                         :: inf_ill,inf_cont,inf_ncont,inf_dth

    Integer,Allocatable             :: start_value_tot(:)

    Real                            :: R0_daily
    Real,Allocatable                :: R0matrix(:,:),connect(:,:)
    Integer,Allocatable             :: healthy_cases_final(:,:,:),&
         ill_ICU_cases_final(:,:,:),immune_cases_final(:,:,:),&
         inf_noncon_cases_final(:,:,:),inf_contag_cases_final(:,:,:),&
         dead_cases_final(:,:,:),ill_contag_cases_final(:,:,:)
    Integer,Allocatable             :: inf_cases(:,:),icu_cases(:,:),healthy_cases(:,:),inf_noncon_cases(:,:),&
         inf_contag_cases(:,:),ill_contag_cases(:,:)
    Integer,Allocatable             :: ill_ICU_cases(:,:),immune_cases(:,:),dead_cases(:,:),dead_cases_bICU(:,:),&
         mod_inf_cases(:,:),org_noncon_cases(:,:)

    Integer                         :: timestep

    Integer,Allocatable             :: tmp_d_new(:),tmp_count(:)
    Integer,Allocatable             :: susceptible(:),contagious_dist_id(:),contagious_index(:),denominator(:),&
         revers_proj(:),final_count(:),dist_id_temp(:),ill_index(:),&
         ill_dist_id(:)
    Real,Allocatable                :: contagious(:)
    Integer                         :: at_risk
    Integer                         :: initial_sick
    Real                            :: n_contagious,between_weight,within_weight
    Real,Allocatable                :: exp_infect(:)
    Integer,Allocatable             :: check_days(:)

    Real,Allocatable                :: risk(:),prob(:),runif(:),prop_target(:)
    Character*10                    :: target_date,temp_date

    Integer,Allocatable             :: sick(:),case_count(:),state_id(:),prop_inf_cases(:),&
         prop_target_inf(:),mod_inf(:)
    Character*6,Allocatable         :: age_sex(:),surv_ill_label(:),surv_icu_label(:)
    Character*6,Allocatable         :: age_sex_dur(:),icu_risk_label(:)
    Character*2,Allocatable         :: temp_character(:)
    Real,Allocatable                :: surv_ill_i(:),die(:),icu_risk_i(:),icu(:),surv_icu_i(:)
    Integer,Allocatable             :: die_count(:),icu_count(:),die_icu_count(:)
    Character*2,Allocatable         :: ch_age(:)
    Character*5,Allocatable         :: ch_sex(:)
    Integer                         :: max_date,n_change
    Character*10                    :: temp_mod
    character(len=:),allocatable    :: seed_date
    Integer                         :: ierror,size_of_process,my_rank
    Integer                         :: index_final(7),block_size
    Integer,Allocatable             :: req(:)

    Real                            :: iter_pass_handle(6)

    Type(tTimer)                    :: timer
    Integer, Dimension(8)           :: rt

    integer                         :: tar

    Real(kind=pt_rk),Dimension(:,:),Allocatable :: R0_effects
    Integer(kind=ik),Dimension(:)  ,Allocatable :: dist_id_cref 
    
    Integer(kind=ik), Dimension(0:16)         :: istate_count
    Integer(kind=ik)                         :: pop_size
    Integer(kind=ik)                         :: num_counties
    Integer(kind=ik)                         :: ii,jj,kk

    Integer(Kind=ik), Allocatable, Dimension(:)     :: c_ref
    Real(Kind=rk)   , Allocatable, Dimension(:,:)   ::  surv_ill_pas
    Real(Kind=rk)   , Allocatable, Dimension(:,:,:) ::  ICU_risk_pasd
    Real(Kind=rk)   , Allocatable, Dimension(:,:)   ::  surv_icu_pas
    
    ! should import some reliable romdon seed generation code here
    !seed_base = ??

    !===========================================================================
    ! Implementation
    !===========================================================================
    call pt_get("#iter",iter)

    index_final = 1

    Allocate(req(size_of_process))

    seed_in_inner_loop = .False.
    seed_mpi_in_inner_loop = .True.

!!!!!-----3.Set seed infections in population ------
    ini_infected = 10
    seed_infections = "data"
    seed_before = 7

!!!!!-----4.define disease characteristics------

    inf_dur = 3
    cont_dur = 2
    ill_dur  = 8
    icu_dur  = 14
    ! icu_per_day = (/0,0,0,0,0,0,0,8/)
    If (Size(icu_per_day) /= ill_dur) Then
       Print *,'Length icu_per_day not equal to ill_dur'
    Endif
    If ((Sum(icu_per_day)/Size(icu_per_day)) /= 1) Then
       Print *,'Mean icu per day not equal to 1'
    End If

    less_contagious = 0.7

    R0_force = 0
    immune_stop = .True.

!!!!!-----5. define reductions in social contacts -----
    call pt_get("#R0change"     ,R0change    )
    call pt_get("#R0delay"      ,R0delay     )
    call pt_get("#R0delay_days" ,R0delay_days)
    call pt_get("#R0delay_type" ,R0delay_type)

    time_n = Maxval(R0change) + 1
    
!!!!!-----7.  Define whether transition probabilities should differ by age and sex
    control_age_sex     = "age"
    days             = 1

    call pt_get("#seed_date",seed_date)
    seed_date        = add_date(seed_date,days)

    days             = -1-seed_before
    seed_before_char = add_date(seed_date,days)
    seed_seq         = generate_seq(seed_before_char,seed_date)
    
    write(un_lf,PTF_sep)
    write(un_lf,PTF_M_A)"Seed sequence for ill cases:",seed_seq
    
    !Derive dates of infections for those that are inf_cont,
    !but are not yet aware about it (will be registered the
    !next two days)
    seed_temp        = add_date(seed_date,cont_dur)
    seed_inf_cont_seq  =  generate_seq(add_date(seed_date,1),seed_temp)

    write(un_lf,PTF_sep)
    write(un_lf,PTF_M_A)"Seed sequence for infected contagious cases:",seed_inf_cont_seq

    !Derive dates of infections for those that are inf_cont,
    !but are not yet aware about it (will be registered the
    !next 3-5 days)
    seed_inf_ncont_seq = generate_seq(add_date(seed_date,cont_dur+1),add_date(seed_date,inf_dur+cont_dur))

    write(un_lf,PTF_sep)
    write(un_lf,PTF_M_A)"Seed sequence for infected non-contagious cases:",seed_inf_ncont_seq

    !! Setup of latin hypercube. ===============================================
    !! This part should done by the code, but here is set manually for 
    !! simplicity. This part should be seperated away into the preprocessing step
    n_direct  = 8
    n_directv = 0
    n_directl = 1
    n_dist    = 0

    If (n_dist > 0) Then
       ! code for randomLHS
       ! since it would not affect the code, it can be apllied later
    Else
       size_lhc = 0                    ! the first position is reserved for sam_size
    End If

    If (n_direct > 0) Then
       size_lhc = size_lhc + n_direct
    End If

    If (n_directl > 0) Then
       size_lhc = size_lhc + size(iol%R0_effect%data)
    End If

    Allocate(lhc(size_lhc,iter))

    ! lhc(1,:)            = pspace%sam_size%param
    Do i = 1,n_direct
       lhc(i,:) = pspace%Ps_scalar_list(i)%param
    End Do

    call pt_get("#sam_size",tmp_i8)
    lhc(1,:) = tmp_i8

    Do i = 1,iter
       lhc(n_direct+1:Size(lhc,dim=1),i) = Reshape(transpose(iol%R0_effect%data),&
            Shape(lhc(n_direct+1:Size(lhc,dim=1),1)))
    End Do
    ! print *, "after reshape is",reshape(pspace%ROeffect_ps%param,shape(lhc(n_direct+1:size(lhc,dim=1),1)))

    If (control_age_sex == "NONE") Then
       ch_age = (/"total"/)
       ch_sex = (/"total"/)
    End If

    If (control_age_sex == "age") Then
       !     ch_age = generate_seq(0,90,5)
       ch_age = (/"0 ","5 ","10","15","20","25","30","35",&
            "40","45","50","55","60",&
            "65","70","75","80","85","90"/)
       ch_sex = (/"total"/)
    End If

    If (control_age_sex == "sex") Then
       ch_age = (/"total"/)
       ch_sex = (/"m","f"/)
    End If

    If (control_age_sex == "age_sex") Then
       !     ch_age = generate_seq(0,90,5)
       ch_age = (/"0 ","5 ","10","15","20","25","30","35",&
            "40","45","50","55","60",&
            "65","70","75","80","85","90"/)
       ch_sex = (/"m","f"/)
    End If


!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!1
!!! the following part was in the loop at R code
!!! in order to aviod to raise problem of memery
!!! allocation and redundent calculation, put it
!!! outside the loop
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    temp = get_index(iol%transpr_age_gr,ch_age)
    temp1= get_index(iol%transpr_sex,ch_sex)
    targert_icu_risk_index = find_and(temp,temp1)

    If (control_age_sex == "age") Then
       If (.Not.Allocated(icu_risk))Then
          Allocate(icu_risk(2*Size(targert_icu_risk_index)))
       Endif
       icu_risk(1:Size(targert_icu_risk_index)) = iol%transpr_icu_risk(targert_icu_risk_index)
       icu_risk(1:Size(targert_icu_risk_index)) = 1.0 - (1.0 - icu_risk(1:Size(targert_icu_risk_index))) ** (1.0/ Real(ill_dur))
       icu_risk(Size(targert_icu_risk_index)+1 : 2* Size(targert_icu_risk_index)) = icu_risk(1:Size(targert_icu_risk_index))
    End If

    If (control_age_sex == "sex") Then
       If (.Not.Allocated(icu_risk))Then
          Allocate(icu_risk(2*19))
       End If
       icu_risk(1:2) = iol%transpr_icu_risk(targert_icu_risk_index)
       icu_risk(1:2) = 1.0 - (1.0 - icu_risk(1:2)) ** (1.0/ ill_dur)
       icu_risk(Size(targert_icu_risk_index)+1 : 2* Size(targert_icu_risk_index)) = icu_risk(2)
       icu_risk(1:Size(targert_icu_risk_index)) = icu_risk(1)
    End If
    !     skip line 960 to 940 in R code
    If (.Not.Allocated(icu_risk_list%age))Then
       Allocate(icu_risk_list%age(Size(icu_risk)*ill_dur))
       Allocate(icu_risk_list%agei(Size(icu_risk)*ill_dur))
       Allocate(icu_risk_list%sex(Size(icu_risk)*ill_dur))
       Allocate(icu_risk_list%risk(Size(icu_risk)*ill_dur))
       Allocate(icu_risk_list%dur(Size(icu_risk)*ill_dur))
    End If

    Do i = 1, ill_dur
       icu_risk_list%age((i-1)*Size(icu_risk)+1: i*Size(icu_risk)) = (/iol%transpr_age_gr(targert_icu_risk_index),&
            iol%transpr_age_gr(targert_icu_risk_index)/)
       icu_risk_list%sex((i-1)*Size(icu_risk)+1:(i-1)*Size(icu_risk)+19) = 'm'
       icu_risk_list%sex((i-1)*Size(icu_risk)+20:i*Size(icu_risk)) = 'f'
       icu_risk_list%risk((i-1)*Size(icu_risk)+1: i*Size(icu_risk)) = icu_risk * icu_per_day(i)
       icu_risk_list%dur((i-1)*Size(icu_risk)+1: i*Size(icu_risk)) = i
    End Do
    Do i = 1,size(icu_risk_list%agei)
       Read(icu_risk_list%age(i),*)icu_risk_list%agei(i)
    End Do

    write(un_lf,PTF_SEP)
    write(un_lf,PTF_M_A)"ICU risk per age group, sex, and duration in ICU."
    Do ii=1, Size(icu_risk)*ill_dur
       write(un_lf,'(A4,I4,A2,F6.3,I3)') &
            icu_risk_list%age(ii)    , icu_risk_list%agei(ii), icu_risk_list%sex(ii), &
            icu_risk_list%risk(ii), icu_risk_list%dur(ii)
    End Do


    Allocate(ICU_risk_pasd( &
         minval(icu_risk_list%agei):maxval(icu_risk_list%agei),&
         1:2, &
         minval(icu_risk_list%dur):maxval(icu_risk_list%dur)))

    Do ii=1, Size(icu_risk)*ill_dur
       if (icu_risk_list%sex(ii) == "m") then
          ICU_risk_pasd(icu_risk_list%agei(ii),1,icu_risk_list%dur(ii)) = icu_risk_list%risk(ii)
       Else
          ICU_risk_pasd(icu_risk_list%agei(ii),2,icu_risk_list%dur(ii)) = icu_risk_list%risk(ii)
       End if
    End Do
    
    ! init surv_ill
    If (control_age_sex == "age") Then
       If (.Not.Allocated(surv_ill))Then
          Allocate(surv_ill(2*Size(targert_icu_risk_index)))
       End If
       surv_ill = (/iol%transpr_surv_ill(targert_icu_risk_index),&
            iol%transpr_surv_ill(targert_icu_risk_index)/)
       surv_ill = surv_ill ** (1.0/Real(ill_dur))
    End If

    If (control_age_sex == "sex") Then
       If (.Not.Allocated(surv_ill))Then
          Allocate(surv_ill(2*19))
       Endif
       surv_ill(1:2) = iol%transpr_surv_ill(targert_icu_risk_index)
       surv_ill(1:2) = 1.0 - (1.0 - surv_ill(1:2)) ** (1.0/ Real(ill_dur))
       surv_ill(Size(targert_icu_risk_index)+1 : 2* Size(targert_icu_risk_index)) = surv_ill(2)
       surv_ill(1:Size(targert_icu_risk_index)) = surv_ill(1)
    End If
    If (.Not.Allocated(surv_ill_list%age))Then
       Allocate(surv_ill_list%age(Size(surv_ill)))
       Allocate(surv_ill_list%agei(Size(surv_ill)))
       Allocate(surv_ill_list%sex(Size(surv_ill)))
       Allocate(surv_ill_list%risk(Size(surv_ill)))
    End If
    surv_ill_list%age = (/iol%transpr_age_gr(targert_icu_risk_index),iol%transpr_age_gr(targert_icu_risk_index)/)
    surv_ill_list%sex = 'f'
    surv_ill_list%sex(1:19) = 'm'
    surv_ill_list%risk  = surv_ill
    Do i = 1, Size(surv_ill)
       Read(surv_ill_list%age(i),*)surv_ill_list%agei(i)
    End Do

    write(un_lf,PTF_SEP)
    write(un_lf,PTF_M_A)"Chance of survival per age group and sex."
    Do ii=1, 2*19
       write(un_lf,'(A4,I4, A2,F6.3)') &
            surv_ill_list%age(ii)    , surv_ill_list%agei(ii), surv_ill_list%sex(ii), &
            surv_ill_list%risk(ii)
    End Do

    allocate(surv_ill_pas(minval(surv_ill_list%agei):maxval(surv_ill_list%agei),1:2))
    Do ii=1, 2*19
       if (surv_ill_list%sex(ii) == "m") then
          surv_ill_pas(surv_ill_list%agei(ii),1) = surv_ill_list%risk(ii)
       Else
          surv_ill_pas(surv_ill_list%agei(ii),2) = surv_ill_list%risk(ii)
       End if
    End Do
    
    ! init surv_icu
    If (control_age_sex == "age") Then
       If (.Not.Allocated(surv_icu))Then
          Allocate(surv_icu(2*Size(targert_icu_risk_index)))
       End If
       surv_icu= (/iol%transpr_surv_icu(targert_icu_risk_index),&
            iol%transpr_surv_icu(targert_icu_risk_index)/)
       surv_icu = surv_icu ** (1/Real(ill_dur))
    End If

    If (control_age_sex == "sex") Then
       If (.Not.Allocated(surv_icu))Then
          Allocate(surv_icu(2*19))
       End If
       surv_icu(1:2) = iol%transpr_surv_icu(targert_icu_risk_index)
       surv_icu(1:2) = 1.0 - (1.0 - surv_icu(1:2)) ** (1.0/ Real(ill_dur))
       surv_icu(Size(targert_icu_risk_index)+1 : 2* Size(targert_icu_risk_index)) = surv_icu(2)
       surv_icu(1:Size(targert_icu_risk_index)) = surv_icu(1)
    End If
    If (.Not.Allocated(surv_icu_list%age))Then
       Allocate(surv_icu_list%age(Size(surv_icu)))
       Allocate(surv_icu_list%agei(Size(surv_icu)))
       Allocate(surv_icu_list%sex(Size(surv_icu)))
       Allocate(surv_icu_list%risk(Size(surv_icu)))
    End If
    surv_icu_list%age = (/iol%transpr_age_gr(targert_icu_risk_index),iol%transpr_age_gr(targert_icu_risk_index)/)
    surv_icu_list%sex = 'f'
    surv_icu_list%sex(1:19) = 'm'
    surv_icu_list%risk  = surv_icu
    Do i = 1, size(surv_icu)
       Read(surv_icu_list%age(i),*)surv_icu_list%agei(i)
    End Do
    
    write(un_lf,PTF_SEP)
    write(un_lf,PTF_M_A)"Chance of survival in ICU per age group and sex."
    Do ii=1, 2*19
       write(un_lf,'(A4,I4,A2,F6.3)') &
            surv_icu_list%age(ii),  surv_icu_list%agei(ii)  , surv_icu_list%sex(ii), &
            surv_icu_list%risk(ii)
    End Do

    allocate(surv_icu_pas(minval(surv_icu_list%agei):maxval(surv_icu_list%agei),1:2))
    Do ii=1, 2*19
       if (surv_icu_list%sex(ii) == "m") then
          surv_icu_pas(surv_icu_list%agei(ii),1) = surv_icu_list%risk(ii)
       Else
          surv_icu_pas(surv_icu_list%agei(ii),2) = surv_icu_list%risk(ii)
       End if
    End Do
    
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!1
!!! the following part was in the loop at R code
!!! put it outside to avoid memoery problem
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    num_counties = Size(counties_index)
    
    Allocate(healthy_cases_final(num_counties,time_n,iter))
    Allocate(inf_noncon_cases_final(num_counties,time_n,iter))
    Allocate(inf_contag_cases_final(num_counties,time_n,iter))
    Allocate(ill_contag_cases_final(num_counties,time_n,iter))
    Allocate(ill_ICU_cases_final(num_counties,time_n,iter))
    Allocate(immune_cases_final(num_counties,time_n,iter))
    Allocate(dead_cases_final(num_counties,time_n,iter))

    Allocate(inf_cases(num_counties,time_n))
    Allocate(icu_cases(num_counties,time_n))

    Allocate(healthy_cases(num_counties,time_n))
    Allocate(inf_noncon_cases(num_counties,time_n))
    Allocate(inf_contag_cases(num_counties,time_n))
    Allocate(ill_contag_cases(num_counties,time_n))
    Allocate(ill_ICU_cases(num_counties,time_n))
    Allocate(immune_cases(num_counties,time_n))
    Allocate(dead_cases(num_counties,time_n))
    Allocate(dead_cases_bICU(num_counties,time_n))
    Allocate(mod_inf_cases(num_counties,time_n))
    Allocate(org_noncon_cases(num_counties,time_n))

    block_size = num_counties * time_n

    max_date = find_max_date(iol%seed_date)

    !** Allocate and setup dist_id cross reference -----------------------------
    allocate(dist_id_cref(minval(counties_index):maxval(counties_index)))
    dist_id_cref = -1
    
    Do ii = 1, num_counties
       dist_id_cref(counties_index(ii)) = ii
    End Do
    
!!!=============================================================================
!!! Iteration over parameter space
!!!=============================================================================
    Do it_ss = 1,  Size(lhc,dim=2)

       call start_timer("Init Sim Loop",reset=.FALSE.)
       
       Call random_Seed()

       !!=======================================================================
       !! Init population                 
       iol%pop_total = Nint(Real(iol%pop_total)/Real(Sum(iol%pop_total))* Real(lhc(1,it_ss)))
       pop_size      = Sum(iol%pop_total)
       
       If (.Not.Allocated(temp_s)) allocate(temp_s(pop_size))
       
       If (.Not.Allocated(sim%dist_id))Then
          Allocate(sim%dist_id(pop_size))
          Allocate(sim%sex(pop_size))
          Allocate(sim%age(pop_size))
          Allocate(sim%agei(pop_size))
          Allocate(sim%t1(pop_size))
          Allocate(sim%t2(pop_size))
          Allocate(sim%d(pop_size))
       Endif

       index = 0 ! position index
       ! set all male for testing

       Do i = 1, Size(iol%pop_total)
          temp_int = iol%pop_total(i)
          sim%dist_id(index+1: index+temp_int) = iol%pop_distid(i)
          sim%sex(index+1: index+temp_int)  = iol%pop_sex(i)
          sim%age(index+1: index+temp_int)  = iol%pop_age(i)
          sim%agei(index+1: index+temp_int) = iol%pop_agei(i)
          index                            = index + temp_int
       End Do

       sim%t1 = healthy
       sim%t2 = missing
       sim%d(:)  = 1

       write(un_lf,PTF_SEP)
       Write(un_lf,PTF_M_AI0)"Size of population is", sum(iol%pop_total)

       !!=======================================================================
       !! seed infections
       temp = get_index(iol%death_distid,counties_index)
       
       iol%death_distid = iol%death_distid(temp)
       iol%death_date   = iol%death_date(temp)
       iol%death_cases  = iol%death_cases(temp)
       !skip line 1113, 1115

       temp = get_index(iol%seed_date,seed_seq)

       seed_ill%dist_id  = iol%seed_distid(temp)
       seed_ill%date     = iol%seed_date(temp)
       seed_ill%cases    = iol%seed_cases(temp)
write(*,*)"sum(seed_ill%cases):",sum(seed_ill%cases)
       temp = get_index(iol%seed_date,seed_inf_cont_seq)

       seed_inf_cont%dist_id  = iol%seed_distid(temp)
       seed_inf_cont%date     = iol%seed_date(temp)
       seed_inf_cont%cases    = iol%seed_cases(temp)
write(*,*)"sum(seed_inf_cont%cases):",sum(seed_inf_cont%cases)
       temp = get_index(iol%seed_date,seed_inf_ncont_seq)
       seed_inf_ncont%dist_id  = iol%seed_distid(temp)
       seed_inf_ncont%date     = iol%seed_date(temp)
       seed_inf_ncont%cases    = iol%seed_cases(temp)
write(*,*)"sum(seed_inf_ncont%cases):",sum(seed_inf_ncont%cases)
       temp_date  =  get_start_date(iol%death_date)
       seed_d_seq = generate_seq(temp_date,add_date(seed_date,-1))
       temp       = get_index(iol%death_date,seed_d_seq)

       iol%death_distid = iol%death_distid(temp)
       iol%death_date   = iol%death_date(temp)
       iol%death_cases  = iol%death_cases(temp)

       If (.Not.Allocated(seed_ill_dur))Then
          Allocate(seed_ill_dur(Size(seed_ill%date)))
       End If

       days             = 0

       seed_date        = add_date(seed_date,days)

       temp_int = Date2Unixtime(seed_date)

       Do i = 1,Size(seed_ill_dur)
          seed_ill_dur(i)  = (temp_int - Date2Unixtime(seed_ill%date(i)))/86400 + 1
       End Do

       temp_int = 1
       !         print *,seed_ill%cases
       !         mod1 = "l"
       !         mod2 = "g"
       temp = condition_and(seed_ill_dur,ill_dur+1,"l",seed_ill%cases,temp_int,"g")
       !          print *,"size of temp",size(temp)
       seed_ill%dist_id  = seed_ill%dist_id(temp)
       seed_ill%date     = seed_ill%date(temp)
       seed_ill%cases    = seed_ill%cases(temp)
       seed_ill_dur      = seed_ill_dur(temp)
write(*,*)"sum(seed_ill%cases):",sum(seed_ill%cases)
       write(un_lf,PTF_SEP)
       write(un_lf,PTF_M_A)"First 20 and last 20 seeds for ill cases."
       Do ii=1, 20
          write(un_lf,'(I6,A12,I6,I6)') &
               seed_ill%dist_id(ii)    , seed_ill%date(ii), &
               seed_ill%cases(ii),seed_ill_dur(ii)
       End Do
       write(un_lf,"('...')")
       Do ii = Size(temp)-19, Size(temp)
          write(un_lf,'(I6,A12,I6,I6)') &
               seed_ill%dist_id(ii)    , seed_ill%date(ii), &
               seed_ill%cases(ii),seed_ill_dur(ii)
       End Do
       
       If (.Not.Allocated(seed_inf_cont_dur))Then
          Allocate(seed_inf_cont_dur(Size(seed_inf_cont%date)))
       End If

       days             = -1
              
       seed_date        = add_date(seed_date,days)

       temp_int = Date2Unixtime(seed_date)

       Do i = 1,Size(seed_inf_cont_dur)
          seed_inf_cont_dur(i)  = (temp_int - Date2Unixtime(seed_inf_cont%date(i)))/86400&
               + cont_dur + 2
       End Do

       if (allocated(temp)) Deallocate(temp)
       Allocate(temp(Size(seed_inf_cont%cases)))

       temp = 0
       temp_int = 0
       Do i = 1,Size(temp)
          If (seed_inf_cont%cases(i)>0) Then
             temp_int = temp_int + 1
             temp(temp_int) = i
          End If
       End Do

       !         seed_inf_cont = set_value(seed_inf_cont,temp(1:temp_int))
       seed_inf_cont%dist_id  = seed_inf_cont%dist_id(temp(1:temp_int))
       seed_inf_cont%date     = seed_inf_cont%date(temp(1:temp_int))
       seed_inf_cont%cases    = seed_inf_cont%cases(temp(1:temp_int))

       write(un_lf,PTF_SEP)
       write(un_lf,PTF_M_A)"First 20 and last 20 seeds for contagious cases."
       Do ii=1, 20
          write(un_lf,'(I6,A12,I6,I6)') &
               seed_inf_cont%dist_id(ii)    , seed_inf_cont%date(ii), &
               seed_inf_cont%cases(ii),seed_inf_cont_dur(ii)
       End Do
       write(un_lf,"('...')")
       Do ii = Size(seed_inf_cont%dist_id)-19, Size(seed_inf_cont%dist_id)
          write(un_lf,'(I6,A12,I6,I6)') &
               seed_inf_cont%dist_id(ii)    , seed_inf_cont%date(ii), &
               seed_inf_cont%cases(ii),seed_inf_cont_dur(ii)
       End Do
       Deallocate(temp)

       If (.Not.Allocated(seed_inf_ncont_dur))Then
          Allocate(seed_inf_ncont_dur(Size(seed_inf_ncont%date)))
       Else
          Deallocate(seed_inf_ncont_dur)
          Allocate(seed_inf_ncont_dur(Size(seed_inf_ncont%date)))
       End If
       temp_int = Date2Unixtime(seed_date)
       Do i = 1,Size(seed_inf_ncont_dur)
          seed_inf_ncont_dur(i)  = (temp_int - Date2Unixtime(seed_inf_ncont%date(i)))/86400&
               + inf_dur + cont_dur + 2
       End Do
       Allocate(temp(Size(seed_inf_ncont%cases)))
       temp = 0
       temp_int = 0
       Do i = 1,Size(temp)
          If (seed_inf_ncont%cases(i)>0) Then
             temp_int = temp_int + 1
             temp(temp_int) = i
          End If
       End Do
       !         seed_inf_ncont = set_value(seed_inf_ncont,temp(1:temp_int))
       seed_inf_ncont%dist_id  = seed_inf_ncont%dist_id(temp(1:temp_int))
       seed_inf_ncont%date     = seed_inf_ncont%date(temp(1:temp_int))
       seed_inf_ncont%cases    = seed_inf_ncont%cases(temp(1:temp_int))

       write(un_lf,PTF_SEP)
       write(un_lf,PTF_M_A)"First 20 and last 20 seeds for non contagious cases."
       Do ii=1, 20
          write(un_lf,'(I6,A12,I6,I6)') &
               seed_inf_ncont%dist_id(ii)    , seed_inf_ncont%date(ii), &
               seed_inf_ncont%cases(ii),seed_inf_ncont_dur(ii)
       End Do
       write(un_lf,"('...')")
       Do ii = Size(seed_inf_ncont%dist_id)-19, Size(seed_inf_ncont%dist_id)
          write(un_lf,'(I6,A12,I6,I6)') &
               seed_inf_ncont%dist_id(ii)    , seed_inf_ncont%date(ii), &
               seed_inf_ncont%cases(ii),seed_inf_ncont_dur(ii)
       End Do

       !       skip line 1163,1166,1169,1172 since the mechanism of 
       !       aggregate is not clear, and it seems not changing anything at all
       !       do scaling
       ! skip scaling ,since they are all 1
       !         seed_ill%cases = seed_ill%cases * sam_prop_ps(seed_ill%dist_id/1000)
       !
       !         seed_inf_cont%cases = seed_inf_cont%cases * sam_prop_ps(seed_ill%dist_id/1000)
       !
       !         seed_inf_ncont%cases = seed_inf_ncont%cases * sam_prop_ps(seed_ill%dist_id/1000)

       write(un_lf,PTF_SEP)
       write(un_lf,PTF_M_A)"Seeds per county."
       write(un_lf,'(5(A10,1X))')"county","inf_ncont","inf_cont","inf_ill","inf_dth"
       
       Do icounty = 1,num_counties

          county = counties_index(icounty)

          rownumbers = get_index(sim%dist_id,county)
!write(*,*)"rownumbers",rownumbers
          temp   = get_index(seed_ill%dist_id,county)
          il_d   = rep(seed_ill_dur(temp),seed_ill%cases(temp))
          inf_ill= Sum(seed_ill%cases(temp))

          temp   = get_index(seed_inf_cont%dist_id,county)
          inf_c_d= rep(seed_inf_cont_dur(temp),seed_inf_cont%cases(temp))

          inf_cont = Sum(seed_inf_cont%cases(temp))

          temp   = get_index(seed_inf_ncont%dist_id,county)
          inf_nc_d = rep(seed_inf_ncont_dur(temp),seed_inf_ncont%cases(temp))
          inf_ncont = Sum(seed_inf_ncont%cases(temp))

          temp   = get_index(iol%death_distid,county)
          inf_dth = Sum(iol%death_cases(temp))

          write(un_lf,'(11(I11))')county,inf_ncont,inf_cont,inf_ill,inf_dth,&
               minval(inf_nc_d),maxval(inf_nc_d),minval(inf_c_d),maxval(inf_c_d),&
               minval(il_d),maxval(il_d)
          
          If(Size(rownumbers)<(inf_ill+inf_cont+inf_ncont+inf_dth)) Then
             Print *,"Number of infected and dead is larger than population size"
             Print *,"only ",Size(rownumbers),"number left"
             Print *,"total cases is",(inf_ill+inf_cont+inf_ncont+inf_dth)
             Print *,"seperate cases are:" ,inf_ill,inf_cont,inf_ncont,inf_dth
             Print *,"timestep is",timestep
             Print *,"it_ss is",it_ss
             Print *,"county is",county
             Print *,"counties are",counties_index
             Print *,"icounty is",icounty
             Call Exit(status)
          End If

          rownumbers_left = rownumbers
          If (inf_ill > 0) Then

             rownumbers_ill = sample(rownumbers_left,inf_ill)
             Call QSortC(rownumbers_ill)
!write(*,*)"rownumbers_ill",rownumbers_ill
             jj = 1
             kk = 1
             Do ii = 1, Size(rownumbers_left)
!write(*,*)kk,rownumbers_left(kk),ii,rownumbers_left(ii),jj,rownumbers_ill(jj)
                if (rownumbers_left(ii) == rownumbers_ill(jj)) then
                   if (jj < inf_ill) then
                      jj = jj + 1
                   End if
                Else
                   rownumbers_left(kk) = rownumbers_left(ii)
                   kk = kk + 1
                End if

             End Do
             !rownumbers_left = rownumbers_left(1:(Size(rownumbers)-inf_ill))
!write(*,*)"rownumbers_left",rownumbers_left
             sim%t1(rownumbers_ill) = ill_contag
             sim%d(rownumbers_ill)  = il_d
          End If

          If ( inf_cont > 0) Then
             rownumbers_cont = sample(rownumbers_left(1:(Size(rownumbers)-inf_ill)),inf_cont)
!write(*,*)"rownumbers_cont",rownumbers_cont
             Call QSortC(rownumbers_cont)             
!write(*,*)"rownumbers_cont",rownumbers_cont
             jj = 1
             kk = 1
             Do ii = 1, Size(rownumbers_left)
!write(*,*)kk,rownumbers_left(kk),ii,rownumbers_left(ii),jj,rownumbers_cont(jj) 
                if (rownumbers_left(ii) == rownumbers_cont(jj)) then
                   if (jj < inf_cont) then
                      jj = jj + 1
                   End if
                Else
                   rownumbers_left(kk) = rownumbers_left(ii)
                   kk = kk + 1
                End if

             End Do
!write(*,*)"rownumbers_left",rownumbers_left
             !rownumbers_left = rownumbers_left(inf_cont+1:Size(rownumbers_left))
             sim%t1(rownumbers_cont)= inf_contag
             sim%d(rownumbers_cont) = inf_c_d
          End If

          If (inf_ncont > 0) Then
             rownumbers_ncont = sample(rownumbers_left(1:(Size(rownumbers)-inf_ill-inf_cont)),inf_ncont)
!write(*,*)"rownumbers_ncont",rownumbers_ncont
             Call QSortC(rownumbers_ncont)
!write(*,*)"rownumbers_ncont",rownumbers_ncont

             jj = 1
             kk = 1
             Do ii = 1, Size(rownumbers_left)
!write(*,*)kk,rownumbers_left(kk),ii,rownumbers_left(ii),jj,rownumbers_ncont(jj) 
                if (rownumbers_left(ii) == rownumbers_ncont(jj)) then
                   if (jj < inf_ncont) then
                      jj = jj + 1
                   End if
                Else
                   rownumbers_left(kk) = rownumbers_left(ii)
                   kk = kk + 1
                End if

             End Do
!write(*,*)"rownumbers_left",rownumbers_left
             !rownumbers_left = rownumbers_left(inf_ncont+1:Size(rownumbers_left))
             sim%t1(rownumbers_ncont) = inf_noncon
             sim%d(rownumbers_ncont)  = inf_nc_d
          End If

          If (inf_dth > 0) Then
             rownumbers_dea = sample(rownumbers_left(1:(Size(rownumbers)-inf_ill-inf_cont-inf_ncont)),inf_dth)
!write(*,*)"rownumbers_dea",rownumbers_dea             
             sim%t1(rownumbers_dea) = dead
          End If

       End Do ! do icounty = 1,size(sim_counties)

       !! ----------------------------------------------------------------------
       !! Convert from Weekly to daily R0_effects ------------------------------
       R0_daily = R0_force *lhc(2,it_ss)/Real(Real(cont_dur)+Real(ill_dur)*less_contagious) + &
            (1-R0_force)*lhc(2,it_ss)/Real(cont_dur+ill_dur)

       ! this block simplifies the if judgment
       If (.Not.Allocated(R0matrix))Then
          Allocate(R0matrix(num_counties,time_n-1))
       End If
       R0matrix = R0_daily
       n_change  = Size(R0change,dim=2)

       Do i = 1,n_change

          !use counties
          ! give up using character to find the number, but use the index directly
          temp  = 8 + (i-1) * Size(iol%R0_effect%data,dim= 2) + (counties_index/1000)

          getchange = lhc(temp,it_ss)

          gettime = generate_seq(R0change(1,i),R0change(2,i),1)

          Do j = 1,Size(gettime)
             R0matrix(:,gettime(j)) = R0matrix(:,gettime(j)) * getchange
          End Do
       End Do

       If (R0delay) Then
          Do i = 1,Size(R0matrix,dim = 1)
             R0matrix(i,:) = smoothing_change(R0matrix(i,:),R0delay_days,R0delay_type)
          End Do
       End If

       !! ----------------------------------------------------------------------
       !! Init result fields
       start_value_tot        = sum_bygroup(sim%t1,sim%dist_id,counties_index,"ill")
       inf_cases(:,1)         = start_value_tot
       icu_cases(:,1)         = 0
       temp_mod = "healthy   "
       healthy_cases(:,1)     = sum_bygroup(sim%t1,sim%dist_id,counties_index,temp_mod)
       temp_mod = "inf_ncon  "
       inf_noncon_cases(:,1)  = sum_bygroup(sim%t1,sim%dist_id,counties_index,temp_mod)
       temp_mod = "inf_con   "
       inf_contag_cases(:,1)  = sum_bygroup(sim%t1,sim%dist_id,counties_index,temp_mod)
       temp_mod = "ill_con   "
       ill_contag_cases(:,1)  = sum_bygroup(sim%t1,sim%dist_id,counties_index,temp_mod)
       temp_mod = "dead      "
       dead_cases(:,1)        = sum_bygroup(sim%t1,sim%dist_id,counties_index,temp_mod)
       ill_ICU_cases(:,1)     = 0
       immune_cases(:,1)      = 0
       dead_cases_bICU(:,1)   = 0
       mod_inf_cases(:,1)     = 0
       org_noncon_cases(:,1)  = 0
       sim%t2                 = missing !sim%t1

       !** Set up dist_id renumbered cross_reference ---------------------------
       sim%dist_id_rn = dist_id_cref(sim%dist_id)

       If (.Not.Allocated(tmp_d_new))Then
          Allocate(tmp_d_new(Size(sim%d)))
       End If

       call end_timer("Init Sim Loop")
    
!!!=============================================================================
!!! Simulation Loop ============================================================
!!!=============================================================================
       call start_timer("Sim Loop",reset=.FALSE.)

       temp = get_index(iol%connect_work_distid,counties_index)

       connect = iol%connect_work(temp,temp)
       Do i = 1,Size(connect,dim=2)
          connect(:,i) = connect(:,i)/Sum(connect(:,i))
       End Do

       Call CoSMic_TimeLoop(time_n, pop_size, size(counties_index), counties_index, &
            Real(R0matrix,rk), Real(connect,rk), surv_ill_pas, ICU_risk_pasd, surv_icu_pas, sim, &
            healthy_cases,inf_noncon_cases,inf_contag_cases,ill_contag_cases,ill_ICU_cases,&
            immune_cases,dead_cases)

       call end_timer("Sim Loop")

       timer = get_timer("Sim Loop")
       write(*,'(A)',ADVANCE="NO")"Time per day:"
       call write_realtime(frac_realtime(diff_realtimes(timer%rt_end,timer%rt_start),time_n))

       healthy_cases_final(:,:,it_ss)    = healthy_cases
       inf_noncon_cases_final(:,:,it_ss) = inf_noncon_cases
       inf_contag_cases_final(:,:,it_ss) = inf_contag_cases
       ill_contag_cases_final(:,:,it_ss) = ill_contag_cases
       ill_ICU_cases_final(:,:,it_ss)    = ill_ICU_cases
       immune_cases_final(:,:,it_ss)     = immune_cases
       dead_cases_final(:,:,it_ss)       = dead_cases

       days             = +1
       
       seed_date        = add_date(seed_date,days)
              
    End Do     ! end do it_ss

    call start_timer("+- Writeout",reset=.FALSE.)
    
    iter_pass_handle = (/lhc(1,iter),lhc(2,iter),lhc(3,iter),&
         lhc(6,iter),lhc(7,iter),lhc(8,iter)/)

    Call write_data_v2(healthy_cases_final,iter_pass_handle,iol%R0_effect%data,counties_index,1)
    Call write_data_v2(inf_noncon_cases_final,iter_pass_handle,iol%R0_effect%data,counties_index,2)
    Call write_data_v2(inf_contag_cases_final,iter_pass_handle,iol%R0_effect%data,counties_index,3)
    Call write_data_v2(ill_contag_cases_final,iter_pass_handle,iol%R0_effect%data,counties_index,4)
    Call write_data_v2(ill_ICU_cases_final,iter_pass_handle,iol%R0_effect%data,counties_index,5)
    Call write_data_v2(immune_cases_final,iter_pass_handle,iol%R0_effect%data,counties_index,6)
    Call write_data_v2(dead_cases_final,iter_pass_handle,iol%R0_effect%data,counties_index,7)
!!$    End If
    call end_timer("+- Writeout")
1000 continue
!!$    Call MPI_Finalize(ierror)

  End Subroutine COVID19_Spatial_Microsimulation_for_Germany


  Subroutine write_data_v2(healthy_cases_final,iter_pass_handle,R0Change,counties_index,type_file)
    Real,Dimension(:)        :: iter_pass_handle(:)
    Real,Dimension(:,:)      :: R0Change
    Real,Allocatable         :: R0change_rep(:,:),R0change_exp(:,:),temp_output(:)
    Integer,Dimension(:,:,:) :: healthy_cases_final
    Integer,Dimension(:)     :: counties_index
    Integer                  :: iter
    Integer                  :: type_file

    Integer :: county_size, count 
    Character*15                :: iter_char(6)
    Character*5,Allocatable     :: R0change_name(:)
    Character*2                 :: counties(16)
    Integer,Allocatable         :: counties_index_out(:),iter_array(:)

    Character*10,Allocatable    :: Label(:)

    Integer date_time(8),i,j,k
    Character*10 b(3)
    Character*4 year
    Character*2 day,month
    Character*8 time
    Character*3 temp_char

    Character*15 dir_prefix

    iter = Size(healthy_cases_final,DIM=3)
    county_size = Size(healthy_cases_final,DIM=1)
    ! print *,"iter is",iter
    ! print "county_size is",county_size
    iter_char = (/"sam_size       ",&
         "R0             ",&
         "icu_dur        ",&
         "w_int          ",&
         "w.obs          ",&
         "w.obs.by.sate  "/)

    counties  = (/"SH","HH","NI","HB","NW","HE","RP","BW","BY","SL",&
         "BE","BB","MV","SN","ST","TH"/)

    Allocate(R0change_rep(Size(R0Change),1))
    Allocate(R0change_exp(iter*county_size,Size(R0change_rep)))
    Allocate(temp_output(iter*county_size))
    Allocate(R0change_name(Size(R0Change)))
    Allocate(iter_array(county_size*iter))
    Allocate(counties_index_out(county_size*iter))
    Allocate(Label(Size(healthy_cases_final,dim=2)))

    Call date_and_Time(b(1),b(2),b(3),date_time)
    
    count = 1
    Do i = 1,Size(counties)
       Do j = 1,Size(R0Change,1)
          Write(temp_char,"(I2)")j
          If (j>9)Then
             R0change_name(count) = counties(i)//temp_char
          Else
             R0change_name(count) = counties(i)//Adjustl(temp_char)
          End If
          count = count + 1
       End Do
    End Do
    count = 1
    Do i =1,Size(healthy_cases_final,dim =2)
       Write(Label(i),"(I3)")i
    End Do


    Write(year,"(I4)")date_time(1)
    Write(month,"(I2)")date_time(2)
    Write(day,"(I2)")date_time(3)
    If (date_time(2)<=9)Then
       month = "0"//Adjustl(month)
    Endif


    dir_prefix = "./output/"

    If(date_time(3)<=9)Then
       day = "0"//Adjustl(day)
    End If
    time = year//month//day
    If (type_file == 1)Then
       Open (101, file = Trim(dir_prefix)//time//"healthy_cases.csv")
    End If

    If (type_file == 2)Then
       Open (101, file = Trim(dir_prefix)//time//"inf_noncon_cases.csv")
    End If

    If (type_file == 3)Then
       Open (101, file = Trim(dir_prefix)//time//"inf_contag_cases.csv")
    End If

    If (type_file == 4)Then
       Open (101, file = Trim(dir_prefix)//time//"ill_contag_cases.csv")
    End If

    If (type_file == 5)Then
       Open (101, file = Trim(dir_prefix)//time//"ill_ICU_cases.csv")
    End If

    If (type_file == 6)Then
       Open (101, file = Trim(dir_prefix)//time//"immune_cases.csv")
    End If

    If (type_file == 7)Then
       Open (101, file = Trim(dir_prefix)//time//"dead_cases.csv")
    End If

10  Format(1x,*(g0,","))

    !write the head file
    Write(101,10)Label,iter_char,R0change_name,"iter","x.dist_id"

    R0change_rep = Reshape(R0Change,(/Size(R0change),1/))
    R0change_exp = Transpose(Spread(R0change_rep(:,1),2,iter*county_size))

    count = 1
    Do i = 1,iter
       Do j = 1,county_size
          Write(101,10)healthy_cases_final(j,:,i),iter_pass_handle,R0change_exp(count,:),&
               i,counties_index(j)
          count = count+1
       End Do
    End Do

    Close(101)
  End Subroutine write_data_v2



  !!============================================================================
  !> Model Timeloop
  Subroutine CoSMic_TimeLoop(&
       time_n, pop_size, n_counties, counties, &
       R0matrix, connect, surv_ill_pas, ICU_risk_pasd, surv_icu_pas, &
       sim, &
       healthy_cases, inf_noncon_cases,inf_contag_cases, ill_contag_cases,&
       ill_ICU_cases, immune_cases,    dead_cases)
    
    Integer(Kind=ik)                       , Intent(In) :: time_n
    Integer(Kind=ik)                       , Intent(In) :: pop_size
    Integer(Kind=ik)                       , Intent(In) :: n_counties
    Integer(Kind=ik), Dimension(n_counties), Intent(In) :: counties
    
    Real(Kind=rk)   , Dimension(n_counties,2:time_n)  , Intent(In) ::  R0matrix
    Real(Kind=rk)   , Dimension(n_counties,n_counties), Intent(In) ::  connect
    Real(Kind=rk)   , Allocatable, Dimension(:,:)     , Intent(In) ::  surv_ill_pas
    Real(Kind=rk)   , Allocatable, Dimension(:,:,:)   , Intent(In) ::  ICU_risk_pasd
    Real(Kind=rk)   , Allocatable, Dimension(:,:)     , Intent(In) ::  surv_icu_pas
    
    Type(sims)                             , Intent(InOut) :: sim

    Integer         , Allocatable, Dimension(:,:), intent(inout)     :: healthy_cases
    Integer         , Allocatable, Dimension(:,:), intent(inout)     :: inf_noncon_cases
    Integer         , Allocatable, Dimension(:,:), intent(inout)     :: inf_contag_cases
    Integer         , Allocatable, Dimension(:,:), intent(inout)     :: ill_contag_cases
    Integer         , Allocatable, Dimension(:,:), intent(inout)     :: ill_ICU_cases
    Integer         , Allocatable, Dimension(:,:), intent(inout)     :: immune_cases
    Integer         , Allocatable, Dimension(:,:), intent(inout)     :: dead_cases


    !> Counters --------------------------------
    Integer(Kind=ik)             :: timestep, ii, nn
    
    Integer(Kind=ik)             :: at_risk, new_in_state
    
    Integer(Kind=ik)             , Dimension(min_state:max_state) :: state_count_t1
    Integer(Kind=ik)             , Dimension(min_state:max_state) :: state_count_t2

    Integer(Kind=ik), Allocatable, Dimension(:,:)              :: state_count_pl
    Real(Kind=rk)   , Allocatable, Dimension(:)                :: risk_pl, risk_pi

    Integer(Kind=ik), Allocatable, Dimension(:)                :: d_new

    Real(kind=rk)                                              :: less_contagious
    Real(kind=rk)                                              :: w_int
    Integer(kind=ik)                                           :: inf_dur, cont_dur, ill_dur, icu_dur

    !===========================================================================

        call start_timer("+- Prepare data",reset=.FALSE.)
       
    !** Allocate and init new counter ----------------------
    Allocate(state_count_pl(min_state:max_state,n_counties))
    state_count_pl = 0
    
    Allocate(risk_pl(n_counties))
    risk_pl = -1._rk

    Allocate(risk_pi(pop_size))
    risk_pi = -1._rk
        
    Allocate(d_new(pop_size))
    d_new = sim%d
    
    call pt_get("#less_contagious", less_contagious)
    call pt_get("#w_int"          , w_int          )
    call pt_get("#inf_dur"        , inf_dur        )
    call pt_get("#cont_dur"       , cont_dur       )
    call pt_get("#ill_dur"        , ill_dur        )
    call pt_get("#icu_dur"        , icu_dur        )
    
    call end_timer("+- Prepare data")

    sim%t2 = sim%t1
    
    Do timestep = 2, time_n

       call start_timer("+- From healthy to infected",reset=.FALSE.)

       !** Population summary --------------------------------------------------
       Call summary_1_int(sim%t1, pop_size, state_count_t1, min_state, max_state)
      
       !** DEBUG --- Population Summary -------------------------------------
       write(un_lf,PTF_SEP)
       write(un_lf,PTF_M_AI0)"Population Summary @ start of step:",timestep
       write(un_lf,'(8(I10))')-1,0,1,2,3,4,5,6
       write(un_lf,'(8(I10))')state_count_t1              
       !** DEBUG ------------------------------------------------------------

       !** Is there something to calculate ? -------------------------
       If ( state_count_t1(dead) + state_count_t1(immune) == pop_size) Then
          write(un_lf,PTF_SEP)
          write(un_lf,PTF_M_A)"All are immune or dead."
          write(un_lf,PTF_SEP)
          exit
       End If
       
       !** Population summary per location -------------------------------------
       Call summary_2_int(&
            sim%t1, sim%dist_id_rn, pop_size, &
            state_count_pl, min_state, max_state,1,n_counties)

       !** DEBUG --- Population Summary -------------------------------------
       write(un_lf,PTF_SEP)
       write(un_lf,PTF_M_AI0)"Population Summary per location @ start of step:",timestep
       write(un_lf,'(A6,8(I10))')"Loc",-1,0,1,2,3,4,5,6
       Do ii = 1, n_counties
          write(un_lf,'(11(I10))')ii,state_count_pl(:,ii)
       End Do
       !** DEBUG ------------------------------------------------------------

       !** Number of people who are at risk in population ---
       at_risk = state_count_t1(healthy)

       risk_pl = state_count_pl(inf_contag,:) +  state_count_pl(ill_contag,:) * less_contagious

       risk_pl = risk_pl * R0matrix(:,timestep)
       
       risk_pl = w_int * risk_pl + (1._rk - w_int) * Matmul (risk_pl, connect)

       Do ii = 1, n_counties
          risk_pl(ii) = risk_pl(ii) / sum(state_count_pl([healthy,immune, &
                                                          inf_noncon,inf_contag, &
                                                          ill_contag              ],ii))
       End Do

       risk_pl = w_int * risk_pl + (1._rk - w_int) * Matmul (risk_pl, connect)
       
       !** DEBUG --- Risk per location --------------------------------------
       write(un_lf,PTF_SEP)
       write(un_lf,PTF_M_AI0)"Risk per location @ timestep:",timestep
       write(un_lf,'(f10.6)')risk_pl
       !** DEBUG ------------------------------------------------------------

       !** Draw risks for all individuals at risk --------------------
       Call random_Number(risk_pi(1:at_risk))
       nn = 1
       Do ii = 1, pop_size

          if ((sim%t1(ii) == healthy)) then
             !** Individual is healthy ----------------------------------
             
             nn = nn + 1

             if (risk_pi(nn) <= risk_pl(sim%dist_id_rn(ii))) then
                !** Individual becomes infected ----------------------
                sim%t2(ii) = inf_noncon
                d_new(ii)  = 1
             Else
                !** Individual stays healthy -------------------------
                d_new(ii) = d_new(ii)  + 1
                
             End if
             
          Else if ((sim%t1(ii) == inf_noncon)) then
             !** Individual is already infected ----------------------
             if (sim%d(ii) >= inf_dur) then
                sim%t2(ii) = inf_contag
                d_new(ii)  = 1
             Else
                d_new(ii) = d_new(ii)  + 1
             End if
             
          Else if ((sim%t1(ii) == inf_contag)) then
             !** Individual is already infected and contagious -------
             if (sim%d(ii) >= cont_dur) then
                sim%t2(ii) = ill_contag
                d_new(ii)  = 1
             Else
                d_new(ii) = d_new(ii) + 1
             End if
          end if
                          
       End Do
       
       !** Population summary --------------------------------------------------
       Call summary_1_int(sim%t2, pop_size, state_count_t2, min_state, max_state)
       
       !** DEBUG --- Population Summary -------------------------------------
       write(un_lf,PTF_SEP)
       write(un_lf,PTF_M_AI0)"Population Summary after infection @ timestep ",timestep
       write(un_lf,'(8(I10))')-1,0,1,2,3,4,5,6
       write(un_lf,'(8(I10))')state_count_t2
       !** DEBUG ------------------------------------------------------------
       
       call end_timer("+- From healthy to infected")
       
       call start_timer("+- From infected to ill and icu",reset=.FALSE.)

       at_risk = state_count_t1(ill_contag)
       write(un_lf,PTF_M_AI0)"At risk to die after infection:",at_risk

       new_in_state = 0
       
       !** Draw risks for all individuals at risk --------------------
       Call random_Number(risk_pi(1:at_risk))
       nn = 1
       Do ii = 1, pop_size

          if (sim%t1(ii) == ill_contag) then
             !** Individual was already ill_contag -------------------
             nn = nn + 1

             if (sim%sex(ii) == "m") then
                if (risk_pi(nn) >= surv_ill_pas(sim%agei(ii),1)) then
                   !** Individual dies -------------------------------
                   sim%t2(ii) = dead
                   d_new(ii)  = 1
                   new_in_state = new_in_state + 1
                End if
             else
                if (risk_pi(nn) >= surv_ill_pas(sim%agei(ii),2)) then
                   !** Individual dies -------------------------------
                   sim%t2(ii) = dead
                   d_new(ii)  = 1
                   new_in_state = new_in_state + 1
                End if
             End if
          End if
       ENd Do

       !** Population summary --------------------------------------------------
       Call summary_1_int(sim%t2, pop_size, state_count_t2, min_state, max_state)
       
       !** DEBUG --- Population Summary -------------------------------------
       write(un_lf,PTF_SEP)
       write(un_lf,PTF_M_AI0)"Population Summary after dying from infection @ timestep ",timestep
       write(un_lf,'(8(I10))')-1,0,1,2,3,4,5,6
       write(un_lf,'(8(I10))')state_count_t2
       !** DEBUG ------------------------------------------------------------

       at_risk = state_count_t1(ill_contag)-new_in_state
       write(un_lf,PTF_M_AI0)"At risk to move to icu:",at_risk

       new_in_state = 0
       
       !** Draw risks for all individuals at risk --------------------
       Call random_Number(risk_pi(1:at_risk))
       nn = 1
       Do ii = 1, pop_size

          if ((sim%t1(ii) == ill_contag) .AND. (sim%t2(ii) == ill_contag)) then
             !** Individual is ill_contag ----------------------------
             nn = nn + 1

             if (sim%sex(ii) == "m") then
                if (risk_pi(nn) <= ICU_risk_pasd(sim%agei(ii),1,sim%d(ii))) then
                   !** Individual moves to icu -----------------------
                   sim%t2(ii) = ill_ICU
                   d_new(ii)  = 1
                Else
                   if (sim%d(ii) >= ill_dur) then
                      !** Individual becomes immune ------------------------
                      sim%t2(ii) = immune
                      d_new(ii)  = 1
                   Else
                      !** Individual stays ill_contagious ------------------
                      d_new(ii) = d_new(ii)  + 1
                   End if
                End if
             else
                if (risk_pi(nn) <= ICU_risk_pasd(sim%agei(ii),2,sim%d(ii))) then
                   !** Individual dies -------------------------------
                   sim%t2(ii) = ill_ICU
                   d_new(ii)  = 1
                Else
                   if (sim%d(ii) >= ill_dur) then
                      !** Individual becomes immune ------------------------
                      sim%t2(ii) = immune
                      d_new(ii)  = 1
                   Else
                      !** Individual stays ill_contagious ------------------
                      d_new(ii) = d_new(ii)  + 1
                   End if
                End if
             End if
          End if
         
       ENd Do

       !** Population summary --------------------------------------------------
       Call summary_1_int(sim%t2, pop_size, state_count_t2, min_state, max_state)
       
       !** DEBUG --- Population Summary -------------------------------------
       write(un_lf,PTF_SEP)
       write(un_lf,PTF_M_AI0)"Population Summary after moving to ICU @ timestep ",timestep
       write(un_lf,'(8(I10))')-1,0,1,2,3,4,5,6
       write(un_lf,'(8(I10))')state_count_t2
       !** DEBUG ------------------------------------------------------------

       call end_timer("+- From infected to ill and icu")

       at_risk = state_count_t1(ill_ICU)
       write(un_lf,PTF_M_AI0)"At risk to die in icu:",at_risk

       !** Draw risks for all individuals at risk --------------------
       Call random_Number(risk_pi(1:at_risk))
       nn = 1
       Do ii = 1, pop_size

          if (sim%t1(ii) == ill_ICU) then
             !** Individual was already ill_ICU ----------------------
             nn = nn + 1

             if (sim%sex(ii) == "m") then
                if (risk_pi(nn) >= surv_icu_pas(sim%agei(ii),1)) then
                   !** Individual moves to icu -----------------------
                   sim%t2(ii) = dead
                   d_new(ii)  = 1
                Else
                   if (sim%d(ii) >= icu_dur) then
                      !** Individual becomes immune ------------------------
                      sim%t2(ii) = immune
                      d_new(ii)  = 1
                   Else
                      !** Individual stays in ICU --------------------------
                      d_new(ii) = d_new(ii)  + 1
                   End if
                End if
             else
                if (risk_pi(nn) >= surv_icu_pas(sim%agei(ii),2)) then
                   !** Individual dies -------------------------------
                   sim%t2(ii) = dead
                   d_new(ii)  = 1
                Else
                   if (sim%d(ii) >= icu_dur) then
                      !** Individual becomes immune ------------------------
                      sim%t2(ii) = immune
                      d_new(ii)  = 1
                   Else
                      !** Individual stays in ICU --------------------------
                      d_new(ii) = d_new(ii)  + 1
                   End if
                End if
             End if
          End if

       End Do

       !** Population summary --------------------------------------------------
       Call summary_1_int(sim%t2, pop_size, state_count_t2, min_state, max_state)
       
       !** DEBUG --- Population Summary -------------------------------------
       write(un_lf,PTF_SEP)
       write(un_lf,PTF_M_AI0)"Population Summary after timestep ",timestep
       write(un_lf,'(8(I10))')-1,0,1,2,3,4,5,6
       write(un_lf,'(8(I10))')state_count_t2
       write(*,'(8(I10))')state_count_t2
       
       !** DEBUG ------------------------------------------------------------

       !** Population summary per location -------------------------------------
       Call summary_2_int(&
            sim%t2, sim%dist_id_rn, pop_size, &
            state_count_pl, min_state, max_state, 1, n_counties)

       healthy_cases(:,timestep)    = state_count_pl(healthy   ,:)
       inf_noncon_cases(:,timestep) = state_count_pl(inf_noncon,:)
       inf_contag_cases(:,timestep) = state_count_pl(inf_contag,:)
       ill_contag_cases(:,timestep) = state_count_pl(ill_contag,:)
       ill_ICU_cases(:,timestep)    = state_count_pl(ill_ICU   ,:)
       immune_cases(:,timestep)     = state_count_pl(immune    ,:)
       dead_cases(:,timestep)       = state_count_pl(dead      ,:)
       
       sim%t1 = sim%t2
       sim%d  = d_new
       
    ENd Do
    
  End Subroutine CoSMic_TimeLoop

  
  Subroutine summary_1_int(arr,nn,cnt,lb,ub)

    Integer(kind=ik), Dimension(nn)    , Intent(in)  :: arr
    Integer(kind=ik)                   , Intent(in)  :: nn,lb,ub
    
    Integer(kind=ik), Dimension(lb:ub) , Intent(Out) :: cnt

    Integer(kind=ik)                             :: ii
    
    cnt = 0

    Do ii = 1, nn      
       cnt(arr(ii)) = cnt(arr(ii)) + 1
    End Do

  End Subroutine summary_1_int

  Subroutine summary_2_int(arr1,arr2,nn, cnt,lb1,ub1,lb2,ub2)

    Integer(kind=ik), Dimension(nn)    , Intent(in)  :: arr1, arr2
    Integer(kind=ik)                   , Intent(in)  :: nn,lb1,ub1,lb2,ub2
    
    Integer(kind=ik), Dimension(lb1:ub1,lb2:ub2) , Intent(Out) :: cnt

    Integer(kind=ik)                             :: ii
    
    cnt = 0

    Do ii = 1, nn      
       cnt(arr1(ii),arr2(ii)) = cnt(arr1(ii),arr2(ii)) + 1
    End Do

  End Subroutine summary_2_int
  
End Module kernel