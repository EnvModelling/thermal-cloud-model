	!>@author
	!>Paul Connolly, The University of Manchester
	!>@brief
	!>advection code for the dynamical cloud model
    module advection_s_3d
    use nrtype
    
    private
    public :: mpdata_3d, mpdata_vec_3d, first_order_upstream_3d, adv_ref_state
    
	contains
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	! Simple first order upstream scheme                                                 !
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	!>@author
	!>Paul J. Connolly, The University of Manchester
	!>@brief
	!>perform 1 time-step of 3-d first order upstream method 
	!>\f$ \frac{\partial \psi}{\partial t} + \nabla \cdot \bar{v} \psi = 0 \f$
	!>@param[in] dt
	!>@param[in] dx,dy,dz
	!>@param[in] ip,jp,kp,l_h,r_h
	!>@param[in] u
	!>@param[in] v
	!>@param[in] w
	!>@param[inout] psi
	subroutine first_order_upstream_3d(dt,dx,dy,dz,rhoa,ip,jp,kp,l_h,r_h,u,v,w,psi)
	use nrtype
	implicit none
	real(sp), intent(in) :: dt
	integer(i4b), intent(in) :: ip, jp, kp, l_h, r_h
	real(sp), dimension(-r_h+1:kp+r_h,-r_h+1:jp+r_h,-l_h+1:ip+r_h), &
		intent(in) :: u
	real(sp), dimension(-r_h+1:kp+r_h,-l_h+1:jp+r_h,-r_h+1:ip+r_h), &
		intent(in) :: v
	real(sp), dimension(-l_h+1:kp+r_h,-r_h+1:jp+r_h,-r_h+1:ip+r_h), &
		intent(in) :: w
	real(sp), dimension(-r_h+1:kp+r_h,-r_h+1:jp+r_h,-r_h+1:ip+r_h), &
		intent(inout) :: psi
	real(sp), dimension(-l_h+1:ip+r_h), intent(in) :: dx
	real(sp), dimension(-l_h+1:jp+r_h), intent(in) :: dy
	real(sp), dimension(-l_h+1:kp+r_h), intent(in) :: dz, rhoa
	
	! locals
	real(sp), dimension(kp,jp,ip) :: fx_r, fx_l, fy_r, fy_l, fz_r, fz_l
	integer(i4b) :: i,j,k

!$omp simd	
	do i=1,ip
		do j=1,jp
			do k=1,kp
			    ! Flux going out of right cell boundary into adjacent cell-x 
				fx_r(k,j,i)=( (u(k,j,i)+abs(u(k,j,i)))*psi(k,j,i)+ &
					(u(k,j,i)-abs(u(k,j,i)))*psi(k,j,i+1) )*dt/ &
					(2._sp*dx(i))
		        ! Flux going through left cell boundary from adjacent cell-x
				fx_l(k,j,i)=( (u(k,j,i-1)+abs(u(k,j,i-1)))*psi(k,j,i-1)+ &
					(u(k,j,i-1)-abs(u(k,j,i-1)))*psi(k,j,i) )*dt/ &
					(2._sp*dx(i))
		
				fy_r(k,j,i)=( (v(k,j,i)+abs(v(k,j,i)))*psi(k,j,i)+ &
					(v(k,j,i)-abs(v(k,j,i)))*psi(k,j+1,i) )*dt/ &
					(2._sp*dy(j))
		
				fy_l(k,j,i)=( (v(k,j-1,i)+abs(v(k,j-1,i)))*psi(k,j-1,i)+ &
					(v(k,j-1,i)-abs(v(k,j-1,i)))*psi(k,j,i) )*dt/ &
					(2._sp*dy(j))
		
				fz_r(k,j,i)=( (w(k,j,i)+abs(w(k,j,i)))*rhoa(k)*psi(k,j,i)+ &
					(w(k,j,i)-abs(w(k,j,i)))*rhoa(k+1)*psi(k+1,j,i) )*dt/ &
					(2._sp*dz(k)*rhoa(k))
		
				fz_l(k,j,i)=( (w(k-1,j,i)+abs(w(k-1,j,i)))*rhoa(k-1)*psi(k-1,j,i)+ &
					(w(k-1,j,i)-abs(w(k-1,j,i)))*rhoa(k)*psi(k,j,i) )*dt/ &
					(2._sp*dz(k)*rhoa(k))
			enddo
		enddo
	enddo
!$omp end simd
	
	! could do a loop here and transport
	psi(1:kp,1:jp,1:ip)=psi(1:kp,1:jp,1:ip)-(fx_r-fx_l)-(fy_r-fy_l)-(fz_r-fz_l)
	end subroutine first_order_upstream_3d
	
	
	
	
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	! multi-dimensional advection using the smolarkiewicz scheme                                                 !
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	!>@author
	!>Paul J. Connolly, The University of Manchester
	!>@brief
	!>advect using 1st order upstream
	!>then re-advect using 1st order upstream with antidiffusive velocities to
	!>correct diffusiveness of the 1st order upstream and iterate
	!>nft option is also coded
	!>solves the 3-d advection equation:
	!>\f$ \frac{\partial \psi}{\partial t} + \nabla \cdot \bar{v} \psi = 0 \f$
	!>@param[in] dt
	!>@param[in] dx,dy,dz, dxn, dyn, dzn
	!>@param[in] ip,jp,kp,l_h,r_h
	!>@param[in] u
	!>@param[in] v
	!>@param[in] w
	!>@param[inout] psi
	!>@param[in] kord, monotone: order of MPDATA and whether it is monotone
	!>@param[in] comm3d, id, dims, coords: mpi variables
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	subroutine mpdata_3d(dt,dx,dy,dz,dxn,dyn,dzn,&
						rhoa,ip,jp,kp,l_h,r_h,u,v,w,psi_in,kord,monotone, comm3d, id, &
						dims,coords)
	use nrtype
	use mpi_module
	use mpi
	
	implicit none
	
	
	integer(i4b), intent(in) :: id, comm3d
	integer(i4b), dimension(3), intent(in) :: dims, coords
	real(sp), intent(in) :: dt
	integer(i4b), intent(in) :: ip, jp, kp, l_h, r_h,kord
	real(sp), dimension(-r_h+1:kp+r_h,-r_h+1:jp+r_h,-l_h+1:ip+r_h), &
		intent(in), target :: u
	real(sp), dimension(-r_h+1:kp+r_h,-l_h+1:jp+r_h,-r_h+1:ip+r_h), &
		intent(in), target :: v
	real(sp), dimension(-l_h+1:kp+r_h,-r_h+1:jp+r_h,-r_h+1:ip+r_h), &
		intent(in), target :: w
	real(sp), dimension(-r_h+1:kp+r_h,-r_h+1:jp+r_h,-r_h+1:ip+r_h), &
		intent(inout), target :: psi_in
	real(sp), dimension(-l_h+1:ip+r_h), intent(in) :: dx, dxn
	real(sp), dimension(-l_h+1:jp+r_h), intent(in) :: dy, dyn
	real(sp), dimension(-l_h+1:kp+r_h), intent(in) :: dz, dzn, rhoa
	logical :: monotone
	
	! locals
	real(sp) :: small=1e-15_sp, &
			u_div1, u_div2, u_div3, u_j_bar1, u_j_bar2, u_j_bar3, &
			denom1, denom2, minlocal, minglobal, psi_local_sum, psi_sum
	integer(i4b) :: i,j,k, it, it2, error
	real(sp), dimension(:,:,:), pointer :: ut
	real(sp), dimension(:,:,:), pointer :: vt
	real(sp), dimension(:,:,:), pointer :: wt
	real(sp), dimension(:,:,:), pointer :: ut_sav
	real(sp), dimension(:,:,:), pointer :: vt_sav
	real(sp), dimension(:,:,:), pointer :: wt_sav
	real(sp), dimension(:,:,:), pointer :: psi, psi_old
	real(sp), dimension(-r_h+1:kp+r_h,-r_h+1:jp+r_h,-l_h+1:ip+r_h), target :: & 
		u_store1, u_store2
	real(sp), dimension(-r_h+1:kp+r_h,-l_h+1:jp+r_h,-r_h+1:ip+r_h), target :: &
		v_store1, v_store2
	real(sp), dimension(-l_h+1:kp+r_h,-r_h+1:jp+r_h,-r_h+1:ip+r_h), target :: &
		w_store1, w_store2
	real(sp), dimension(-r_h+1:kp+r_h,-r_h+1:jp+r_h,-r_h+1:ip+r_h), target :: psi_store
	real(sp), dimension(-r_h+1:kp+r_h,-r_h+1:jp+r_h,-r_h+1:ip+r_h) :: &
						psi_i_max, psi_i_min, psi_j_max,psi_j_min,psi_k_max,psi_k_min, &
						beta_i_up, beta_i_down,&
						beta_j_up, beta_j_down,&
						beta_k_up, beta_k_down
	

	! has to be positive definite
	minlocal=minval(psi_in(1:kp,1:jp,1:ip))
	call mpi_allreduce(minlocal,minglobal,1,MPI_REAL8,MPI_MIN, comm3d,error)

	psi_in=psi_in-minglobal
	
	psi_local_sum=sum(psi_in(1:kp,1:jp,1:ip))
	call MPI_Allreduce(psi_local_sum, psi_sum, 1, MPI_REAL8, MPI_SUM, comm3d, error)
 	if(psi_sum.lt.small) return
	
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	! associate pointers to targets                                                      !
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	ut => u	
	vt => v	
	wt => w	
	ut_sav => u_store1
	vt_sav => v_store1
	wt_sav => w_store1
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	

	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	! if kord > 1 we need a copy of the scalar field                                     !
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	if (kord > 1) then
		psi_store = psi_in   ! array copy
		psi => psi_store	
	endif
	psi_old     => psi_in	
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	
	it2=0
	do it=1,kord
		
		if(it > 1) then
			it2=it2+1
!$omp simd	
			do i=1,ip
				do j=1,jp
					do k=1,kp
						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
						! calculate the anti-diffusive velocities                        !
						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!





						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
						! for divergent flow: eq 38 smolarkiewicz 1984 
						! last part of u wind:
						u_div1=(wt(k,j,i)+wt(k,j,i+1)-wt(k-1,j,i)-wt(k-1,j,i+1)) &
								/ dzn(k-1) + &
								(vt(k,j,i)+vt(k,j,i+1)-vt(k,j-1,i)-vt(k,j-1,i+1)) &
								/ dyn(j-1)
						! for divergent flow: eq 38 smolarkiewicz 1984 
						! last part of v wind:
						u_div2=(wt(k,j,i)+wt(k,j+1,i)-wt(k-1,j,i)-wt(k-1,j+1,i)) &
								/ dzn(k-1) + &
								(ut(k,j,i)+ut(k,j+1,i)-ut(k,j,i-1)-ut(k,j+1,i-1)) &
								/ dxn(i-1)
						! for divergent flow: eq 38 smolarkiewicz 1984 
						! last part of w wind:
						u_div3=(ut(k,j,i)+ut(k+1,j,i)-ut(k,j,i-1)-ut(k+1,j,i-1)) &
								/ dxn(i-1) + &
								(vt(k,j,i)+vt(k+1,j,i)-vt(k,j-1,i)-vt(k+1,j-1,i)) &
								/ dyn(j-1)
						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!



	
						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
						! equation 13 page 330 of smolarkiewicz (1984) 
						! journal of computational physics
						! second term of u wind:
						u_j_bar1 = 0.5_sp*dt*ut(k,j,i) * ( &
							! equation 14:
							0.25_sp*(wt(k,j,i+1)+wt(k,j,i)+wt(k-1,j,i+1)+wt(k-1,j,i)) * &
							! equation 13:
						   ( psi_old(k+1,j,i+1)+psi_old(k+1,j,i)- &
						     psi_old(k-1,j,i+1)-psi_old(k-1,j,i) ) / &
						   ( psi_old(k+1,j,i+1)+psi_old(k+1,j,i)+ &
						     psi_old(k-1,j,i+1)+psi_old(k-1,j,i)+small ) / &
						     ( 0.5_sp*(dzn(k-1)+dzn(k)) ) + &
						    ! repeat for y dimension:
							! equation 14:
							0.25_sp*(vt(k,j,i+1)+vt(k,j,i)+vt(k,j-1,i+1)+vt(k,j-1,i)) * &
							! equation 13:
						   ( psi_old(k,j+1,i+1)+psi_old(k,j+1,i)- &
						     psi_old(k,j-1,i+1)-psi_old(k,j-1,i) ) / &
						   ( psi_old(k,j+1,i+1)+psi_old(k,j+1,i)+ &
						     psi_old(k,j-1,i+1)+psi_old(k,j-1,i)+small ) / &
						     ( 0.5_sp*(dyn(j-1)+dyn(j)) ) )
						     
						     
						! equation 13 page 330 of smolarkiewicz (1984) 
						! journal of computational physics
						! second term of v wind:
						u_j_bar2 = 0.5_sp*dt*vt(k,j,i) * ( &
							! equation 14:
							0.25_sp*(wt(k,j+1,i)+wt(k,j,i)+wt(k-1,j+1,i)+wt(k-1,j,i)) * &
							! equation 13:
						   ( psi_old(k+1,j+1,i)+psi_old(k+1,j,i)- &
						     psi_old(k-1,j+1,i)-psi_old(k-1,j,i) ) / &
						   ( psi_old(k+1,j+1,i)+psi_old(k+1,j,i)+ &
						     psi_old(k-1,j+1,i)+psi_old(k-1,j,i)+small ) / &
						     ( 0.5_sp*(dzn(k-1)+dzn(k)) ) + &
						    ! repeat for y dimension:
							! equation 14:
							0.25_sp*(ut(k,j+1,i)+ut(k,j,i)+ut(k,j+1,i-1)+ut(k,j,i-1)) * &
							! equation 13:
						   ( psi_old(k,j+1,i+1)+psi_old(k,j,i+1)- &
						     psi_old(k,j+1,i-1)-psi_old(k,j,i-1) ) / &
						   ( psi_old(k,j+1,i+1)+psi_old(k,j,i+1)+ &
						     psi_old(k,j+1,i-1)+psi_old(k,j,i-1)+small ) / &
						     ( 0.5_sp*(dxn(i-1)+dxn(i)) ) )
						     
						! equation 13 page 330 of smolarkiewicz (1984) 
						! journal of computational physics
						! second term of w wind:
						u_j_bar3 = 0.5_sp*dt*wt(k,j,i) * ( &
							! equation 14:
							0.25_sp*(vt(k+1,j,i)+vt(k,j,i)+vt(k+1,j-1,i)+vt(k,j-1,i)) * &
							! equation 13:
						   ( psi_old(k+1,j+1,i)+psi_old(k,j+1,i)- &
						     psi_old(k+1,j-1,i)-psi_old(k,j-1,i) ) / &
						   ( psi_old(k+1,j+1,i)+psi_old(k,j+1,i)+ &
						     psi_old(k+1,j-1,i)+psi_old(k,j-1,i)+small ) / &
						     ( 0.5_sp*(dyn(j-1)+dyn(j)) ) + &
						    ! repeat for y dimension:
							! equation 14:
							0.25_sp*(ut(k+1,j,i)+ut(k,j,i)+ut(k+1,j,i-1)+ut(k,j,i-1)) * &
							! equation 13:
						   ( psi_old(k+1,j,i+1)+psi_old(k,j,i+1)- &
						     psi_old(k+1,j,i-1)-psi_old(k,j,i-1) ) / &
						   ( psi_old(k+1,j,i+1)+psi_old(k,j,i+1)+ &
						     psi_old(k+1,j,i-1)+psi_old(k,j,i-1)+small ) / &
						     ( 0.5_sp*(dxn(i-1)+dxn(i)) ) )
						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!




						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
						! last update of equation 13
						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
						! u wind:
						ut_sav(k,j,i)=(abs(ut(k,j,i))*dx(i)-dt*ut(k,j,i)*ut(k,j,i) ) * &
							(psi_old(k,j,i+1)-psi_old(k,j,i) ) / &
							(psi_old(k,j,i+1)+psi_old(k,j,i)+small) /dx(i) - u_j_bar1
						! v wind:
						vt_sav(k,j,i)=(abs(vt(k,j,i))*dy(j)-dt*vt(k,j,i)*vt(k,j,i) ) * &
							(psi_old(k,j+1,i)-psi_old(k,j,i) ) / &
							(psi_old(k,j+1,i)+psi_old(k,j,i)+small) /dy(j) - u_j_bar2														
						! w wind:
						wt_sav(k,j,i)=(abs(wt(k,j,i))*dz(k)-dt*wt(k,j,i)*wt(k,j,i) ) * &
							(psi_old(k+1,j,i)-psi_old(k,j,i) ) / &
							(psi_old(k+1,j,i)+psi_old(k,j,i)+small) /dz(k) - u_j_bar3
						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
							
						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
						! last update of eq 38 smolarkiewicz 1984
						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
						ut_sav(k,j,i)=ut_sav(k,j,i) - 0.25_sp*dt*ut(k,j,i) * &
						 ( (ut(k,j,i+1)-ut(k,j,i-1))/(0.5_sp*(dxn(i-1)+dxn(i)))-u_div1 )
						vt_sav(k,j,i)=vt_sav(k,j,i) - 0.25_sp*dt*vt(k,j,i) * &
						 ( (vt(k,j+1,i)-vt(k,j-1,i))/(0.5_sp*(dyn(j-1)+dyn(j)))-u_div2 )
						wt_sav(k,j,i)=wt_sav(k,j,i) - 0.25_sp*dt*wt(k,j,i) * &
						 ( (wt(k+1,j,i)-wt(k-1,j,i))/(0.5_sp*(dzn(k-1)+dzn(k)))-u_div3 )
						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


					enddo
				enddo
			enddo
!$omp end simd

			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			! associate pointers to targets                                              !
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			if(modulo(it2,2).eq.1) then  
										 
				ut => u_store1
				vt => v_store1
				wt => w_store1
				ut_sav => u_store2
				vt_sav => v_store2
				wt_sav => w_store2
			else if(modulo(it2,2).eq.0) then			
				ut => u_store2
				vt => v_store2
				wt => w_store2
				ut_sav => u_store1
				vt_sav => v_store1
				wt_sav => w_store1
			endif
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			call exchange_full(comm3d, id, kp, jp, ip, r_h,r_h,r_h,r_h,l_h,r_h, &
														ut,dims,coords)
			call exchange_full(comm3d, id, kp, jp, ip, r_h,r_h,l_h,r_h,r_h,r_h, &
														vt,dims,coords)
			call exchange_full(comm3d, id, kp, jp, ip, l_h,r_h,r_h,r_h,r_h,r_h, &
														wt,dims,coords)
		endif
		
		
		
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        ! Non oscillatory forward in time (NFT) flux limiter -                           !
        ! Smolarkiewicz and Grabowski (1990)                                             !
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
		if( (it > 1) .and. monotone) then
			it2=it2+1
		
		
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			! equations 20a and b of Smolarkiewicz and Grabowski (1990, JCP, 86)         !
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!$omp simd	
			do i=1,ip
				do j=1,jp
					do k=1,kp			
						! x direction - note: should the last q in the max/min be q+1?
						psi_i_max(k,j,i)=max(psi(k,j,i-1),psi(k,j,i),psi(k,j,i+1), &
									psi_old(k,j,i-1),psi_old(k,j,i),psi_old(k,j,i+1))
					
						psi_i_min(k,j,i)=min(psi(k,j,i-1),psi(k,j,i),psi(k,j,i+1), &
									psi_old(k,j,i-1),psi_old(k,j,i),psi_old(k,j,i+1))
					enddo
				enddo
			enddo
!$omp end simd

!$omp simd	
			do i=1,ip
				do j=1,jp
					do k=1,kp			
						! y direction - note: should the last q in the max/min be q+1?
						psi_j_max(k,j,i)=max(psi(k,j-1,i),psi(k,j,i),psi(k,j+1,i), &
									psi_old(k,j-1,i),psi_old(k,j,i),psi_old(k,j+1,i))
					
						psi_j_min(k,j,i)=min(psi(k,j-1,i),psi(k,j,i),psi(k,j+1,i), &
									psi_old(k,j-1,i),psi_old(k,j,i),psi_old(k,j+1,i))
					enddo
				enddo
			enddo
!$omp end simd

!$omp simd	
			do i=1,ip
				do j=1,jp
					do k=1,kp			
						! z direction - note: should the last q in the max/min be q+1?
						psi_k_max(k,j,i)=max(psi(k-1,j,i),psi(k,j,i),psi(k+1,j,i), &
									psi_old(k-1,j,i),psi_old(k,j,i),psi_old(k+1,j,i))
					
						psi_k_min(k,j,i)=min(psi(k-1,j,i),psi(k,j,i),psi(k+1,j,i), &
									psi_old(k-1,j,i),psi_old(k,j,i),psi_old(k+1,j,i))
					enddo
				enddo
			enddo
!$omp end simd
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!





			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			! Equations 19a and b of Smolarkiewicz and Grabowski (1990, JCP)             !
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!$omp simd	
			do i=1,ip
				do j=1,jp
					do k=1,kp		
						denom1=(dt*((max(ut(k,j,i-1),0._sp)*psi_old(k,j,i-1)- &
								  min(ut(k,j,i),0._sp)*psi_old(k,j,i+1))/dxn(i-1)+ &
							    (max(vt(k,j-1,i),0._sp)*psi_old(k,j-1,i)-&
								  min(vt(k,j,i),0._sp)*psi_old(k,j+1,i))/dyn(j-1) + &
							    (max(wt(k-1,j,i),0._sp)*psi_old(k-1,j,i)-&
								  min(wt(k,j,i),0._sp)*psi_old(k+1,j,i))/dzn(k-1) &
								  +small))
								  
						denom2=(dt*((max(ut(k,j,i),0._sp)*psi_old(k,j,i)- &
							      min(ut(k,j,i-1),0._sp)*psi_old(k,j,i))/dxn(i-1) + &
								(max(vt(k,j,i),0._sp)*psi_old(k,j,i)-&
								  min(vt(k,j-1,i),0._sp)*psi_old(k,j,i))/dyn(j-1) + &
								(max(wt(k,j,i),0._sp)*psi_old(k,j,i)-&
								  min(wt(k-1,j,i),0._sp)*psi_old(k,j,i))/dzn(k-1) &
								  +small))
								  
						beta_i_up(k,j,i)=(psi_i_max(k,j,i)-psi_old(k,j,i)) / denom1
							
								  
						beta_i_down(k,j,i)=(psi_old(k,j,i)-psi_i_min(k,j,i)) / denom2
											

						beta_j_up(k,j,i)=(psi_j_max(k,j,i)-psi_old(k,j,i)) / denom1
								  
						beta_j_down(k,j,i)=(psi_old(k,j,i)-psi_j_min(k,j,i)) / denom2

						beta_k_up(k,j,i)=(psi_k_max(k,j,i)-psi_old(k,j,i)) / denom1
								  
						beta_k_down(k,j,i)=(psi_old(k,j,i)-psi_k_min(k,j,i)) / denom2
					enddo
				enddo
			enddo 
!$omp end simd
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!



			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			! exchange halos for beta_i_up, down
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			call exchange_along_dim(comm3d, id, kp, jp, ip, r_h,r_h,r_h,r_h,r_h,r_h, &
														beta_i_up,dims,coords)
			call exchange_along_dim(comm3d, id, kp, jp, ip, r_h,r_h,r_h,r_h,r_h,r_h, &
														beta_i_down,dims,coords)
			call exchange_along_dim(comm3d, id, kp, jp, ip, r_h,r_h,r_h,r_h,r_h,r_h, &
														beta_j_up,dims,coords)
			call exchange_along_dim(comm3d, id, kp, jp, ip, r_h,r_h,r_h,r_h,r_h,r_h, &
														beta_j_down,dims,coords)
			call exchange_along_dim(comm3d, id, kp, jp, ip, r_h,r_h,r_h,r_h,r_h,r_h, &
														beta_k_up,dims,coords)
			call exchange_along_dim(comm3d, id, kp, jp, ip, r_h,r_h,r_h,r_h,r_h,r_h, &
														beta_k_down,dims,coords)
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

								
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			! equation 18 of Smolarkiewicz and Grabowski (1990, JCP, 86)                 !
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!$omp simd	
			do i=1,ip
				do j=1,jp
					do k=1,kp			
						ut_sav(k,j,i)=min(1._sp,beta_i_down(k,j,i), &
										 beta_i_up(k,j,i+1))*max(ut(k,j,i),0._sp) + &
									  min(1._sp,beta_i_up(k,j,i), &
									     beta_i_down(k,j,i+1))*min(ut(k,j,i),0._sp)
						vt_sav(k,j,i)=min(1._sp,beta_j_down(k,j,i), &
										 beta_j_up(k,j+1,i))*max(vt(k,j,i),0._sp) + &
									  min(1._sp,beta_j_up(k,j,i), &
									     beta_j_down(k,j+1,i))*min(vt(k,j,i),0._sp)
						wt_sav(k,j,i)=min(1._sp,beta_k_down(k,j,i), &
										 beta_k_up(k+1,j,i))*max(wt(k,j,i),0._sp) + &
									  min(1._sp,beta_k_up(k,j,i), &
									     beta_k_down(k+1,j,i))*min(wt(k,j,i),0._sp)
					enddo
				enddo
			enddo 
!$omp end simd
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			! associate pointers to targets                                              !
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			ut => u_store2
			vt => v_store2
			wt => w_store2
			ut_sav => u_store1
			vt_sav => v_store1
			wt_sav => w_store1
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			call exchange_full(comm3d, id, kp, jp, ip, r_h,r_h,r_h,r_h,l_h,r_h, &
														ut,dims,coords)
			call exchange_full(comm3d, id, kp, jp, ip, r_h,r_h,l_h,r_h,r_h,r_h, &
														vt,dims,coords)
			call exchange_full(comm3d, id, kp, jp, ip, l_h,r_h,r_h,r_h,r_h,r_h, &
														wt,dims,coords)

		endif
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!




		!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
		! advect using first order upwind                                                !
		!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
		call first_order_upstream_3d(dt,dx,dy,dz,rhoa,&
				ip,jp,kp,l_h,r_h,ut,vt,wt,psi_old)
		!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


		
		if((it <= kord) .and. (kord >= 1)) then
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			! set halos																	 !
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!		
			call exchange_full(comm3d, id, kp, jp, ip, r_h,r_h,r_h,r_h,r_h,r_h, &
									psi_old,dims,coords)
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!			
		endif		
 	enddo
 

	! no dangling pointers
	if (associated(ut) ) nullify(ut)
	if (associated(vt) ) nullify(vt)
	if (associated(wt) ) nullify(wt)
	if (associated(ut_sav) ) nullify(ut_sav)
	if (associated(vt_sav) ) nullify(vt_sav)
	if (associated(wt_sav) ) nullify(wt_sav)
	if (associated(psi) ) nullify(psi)
	if (associated(psi_old) ) nullify(psi_old)

	psi_in=psi_in+minglobal
	end subroutine mpdata_3d
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	
	
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	! advect the reference state                                                         !
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	!>@author
	!>Paul J. Connolly, The University of Manchester
	!>@brief
	!>advect using mid-point rule (average of forward and backward Euler)
	!>@param[in] dt
	!>@param[in] dz, dzn
	!>@param[in] ip,jp,kp,l_h,r_h
	!>@param[in] w
	!>@param[inout] psi_3d
	!>@param[in] psi_ref
	!>@param[in] dims, coords: (for the cartesian topology)
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	subroutine adv_ref_state(dt,dz,dzn,&
						rhoa,rhoan,ip,jp,kp,l_h,r_h,w,psi_3d,psi_ref,dims,coords)
						
		implicit none
		 
		real(sp), intent(in) :: dt
		real(sp), dimension(-l_h+1:kp+r_h), intent(in) :: rhoa, rhoan,dz, dzn, psi_ref
		integer(i4b), intent(in) :: ip, jp, kp, l_h, r_h
		real(sp), dimension(-l_h+1:kp+r_h,-r_h+1:jp+r_h,-r_h+1:ip+r_h), intent(in) :: w
		real(sp), dimension(-r_h+1:kp+r_h,-r_h+1:jp+r_h,-r_h+1:ip+r_h), &
							intent(inout) :: psi_3d
		integer(i4b), dimension(3), intent(in) :: dims, coords
		! locals:
		integer(i4b) :: i, j, k
		
		do i=1-r_h,ip+r_h
			do j=1-r_h,jp+r_h
				do k=1,kp
					psi_3d(k,j,i) = psi_3d(k,j,i) &
								- dt*(0.5_sp/dz(k)*w(k-1,j,i)*&
								rhoan(k-1)*(psi_ref(k)-psi_ref(k-1)) &
									 + 0.5_sp/dz(k)*w(k,j,i)* &
								rhoan(k)*(psi_ref(k+1)-psi_ref(k)))/rhoa(k)
				enddo
			enddo
		enddo
		! bit of a fudge, because this method leads to temperature perturbations
		! at surface
		if(coords(3) == 0) psi_3d(1-r_h:1,:,:)=0._sp		
		
	end subroutine adv_ref_state
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!




		

	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	! multi-dimensional vector advection using the smolarkiewicz scheme                                                 !
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	!>@author
	!>Paul J. Connolly, The University of Manchester
	!>@brief
	!>advect using 1st order upstream
	!>then re-advect using 1st order upstream with antidiffusive velocities to
	!>correct diffusiveness of the 1st order upstream and iterate
	!>nft option is also coded
	!>solves the 3-d advection equation:
	!>\f$ \frac{\partial \psi}{\partial t} + \nabla \cdot \bar{v} \psi = 0 \f$
	!>@param[in] dt
	!>@param[in] dx,dy,dz, dxn, dyn, dzn
	!>@param[in] ip,jp,kp,nq,l_h,r_h
	!>@param[in] u
	!>@param[in] v
	!>@param[in] w
	!>@param[inout] psi
	!>@param[in] kord, monotone: order of MPDATA and whether it is monotone
	!>@param[in] comm3d, id, dims, coords: mpi variables
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	subroutine mpdata_vec_3d(dt,dx,dy,dz,dxn,dyn,dzn,&
						rhoa,ip,jp,kp,nq,l_h,r_h,u,v,w,psi_in,kord,monotone, comm3d, id, &
						dims,coords)
	use nrtype
	use mpi_module
	use mpi
	
	implicit none
	
	
	integer(i4b), intent(in) :: id, comm3d
	integer(i4b), dimension(3), intent(in) :: dims, coords
	real(sp), intent(in) :: dt
	integer(i4b), intent(in) :: ip, jp, kp, nq,l_h, r_h,kord
	real(sp), dimension(-r_h+1:kp+r_h,-r_h+1:jp+r_h,-l_h+1:ip+r_h), &
		intent(in), target :: u
	real(sp), dimension(-r_h+1:kp+r_h,-l_h+1:jp+r_h,-r_h+1:ip+r_h), &
		intent(in), target :: v
	real(sp), dimension(-l_h+1:kp+r_h,-r_h+1:jp+r_h,-r_h+1:ip+r_h), &
		intent(in), target :: w
	real(sp), dimension(-r_h+1:kp+r_h,-r_h+1:jp+r_h,-r_h+1:ip+r_h,1:nq), &
		intent(inout), target :: psi_in
	real(sp), dimension(-l_h+1:ip+r_h), intent(in) :: dx, dxn
	real(sp), dimension(-l_h+1:jp+r_h), intent(in) :: dy, dyn
	real(sp), dimension(-l_h+1:kp+r_h), intent(in) :: dz, dzn, rhoa
	logical :: monotone
	
	! locals
	real(sp) :: small=1e-15_sp, &
			u_div1, u_div2, u_div3, u_j_bar1, u_j_bar2, u_j_bar3, &
			denom1, denom2, minlocal, psi_local_sum, psi_sum
	real(sp), dimension(nq) :: minglobal
	integer(i4b) :: i,j,k, it, it2, n,error
	real(sp), dimension(:,:,:), pointer :: ut
	real(sp), dimension(:,:,:), pointer :: vt
	real(sp), dimension(:,:,:), pointer :: wt
	real(sp), dimension(:,:,:), pointer :: ut_sav
	real(sp), dimension(:,:,:), pointer :: vt_sav
	real(sp), dimension(:,:,:), pointer :: wt_sav
	real(sp), dimension(:,:,:), pointer :: psi, psi_old
	real(sp), dimension(-r_h+1:kp+r_h,-r_h+1:jp+r_h,-l_h+1:ip+r_h), target :: & 
		u_store1, u_store2
	real(sp), dimension(-r_h+1:kp+r_h,-l_h+1:jp+r_h,-r_h+1:ip+r_h), target :: &
		v_store1, v_store2
	real(sp), dimension(-l_h+1:kp+r_h,-r_h+1:jp+r_h,-r_h+1:ip+r_h), target :: &
		w_store1, w_store2
	real(sp), dimension(-r_h+1:kp+r_h,-r_h+1:jp+r_h,-r_h+1:ip+r_h,1:nq), target :: psi_store
	real(sp), dimension(-r_h+1:kp+r_h,-r_h+1:jp+r_h,-r_h+1:ip+r_h) :: &
						psi_i_max, psi_i_min, psi_j_max,psi_j_min,psi_k_max,psi_k_min, &
						beta_i_up, beta_i_down,&
						beta_j_up, beta_j_down,&
						beta_k_up, beta_k_down
	

	! has to be positive definite
	do n=1,nq
        minlocal=minval(psi_in(1:kp,1:jp,1:ip,n))
        call mpi_allreduce(minlocal,minglobal(n),1,MPI_REAL8,MPI_MIN, comm3d,error)
        psi_in(:,:,:,n)=psi_in(:,:,:,n)-minglobal(n)
	enddo
	
	psi_local_sum=sum(psi_in(1:kp,1:jp,1:ip,1))
	call MPI_Allreduce(psi_local_sum, psi_sum, 1, MPI_REAL8, MPI_SUM, comm3d, error)
 	if(psi_sum.lt.small) return
	
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	! associate pointers to targets                                                      !
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	ut => u	
	vt => v	
	wt => w	
	ut_sav => u_store1
	vt_sav => v_store1
	wt_sav => w_store1
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	

	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	! if kord > 1 we need a copy of the scalar field                                     !
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	if (kord > 1) then
		psi_store = psi_in   ! array copy
		psi(-r_h+1:kp+r_h,-r_h+1:jp+r_h,-r_h+1:ip+r_h) => psi_store(:,:,:,1)
	endif
	psi_old(-r_h+1:kp+r_h,-r_h+1:jp+r_h,-r_h+1:ip+r_h)     => psi_in(:,:,:,1)
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	
	it2=0
	do it=1,kord
		
		if(it > 1) then
			it2=it2+1
!$omp simd	
			do i=1,ip
				do j=1,jp
					do k=1,kp
						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
						! calculate the anti-diffusive velocities                        !
						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!





						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
						! for divergent flow: eq 38 smolarkiewicz 1984 
						! last part of u wind:
						u_div1=(wt(k,j,i)+wt(k,j,i+1)-wt(k-1,j,i)-wt(k-1,j,i+1)) &
								/ dzn(k-1) + &
								(vt(k,j,i)+vt(k,j,i+1)-vt(k,j-1,i)-vt(k,j-1,i+1)) &
								/ dyn(j-1)
						! for divergent flow: eq 38 smolarkiewicz 1984 
						! last part of v wind:
						u_div2=(wt(k,j,i)+wt(k,j+1,i)-wt(k-1,j,i)-wt(k-1,j+1,i)) &
								/ dzn(k-1) + &
								(ut(k,j,i)+ut(k,j+1,i)-ut(k,j,i-1)-ut(k,j+1,i-1)) &
								/ dxn(i-1)
						! for divergent flow: eq 38 smolarkiewicz 1984 
						! last part of w wind:
						u_div3=(ut(k,j,i)+ut(k+1,j,i)-ut(k,j,i-1)-ut(k+1,j,i-1)) &
								/ dxn(i-1) + &
								(vt(k,j,i)+vt(k+1,j,i)-vt(k,j-1,i)-vt(k+1,j-1,i)) &
								/ dyn(j-1)
						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!



	
						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
						! equation 13 page 330 of smolarkiewicz (1984) 
						! journal of computational physics
						! second term of u wind:
						u_j_bar1 = 0.5_sp*dt*ut(k,j,i) * ( &
							! equation 14:
							0.25_sp*(wt(k,j,i+1)+wt(k,j,i)+wt(k-1,j,i+1)+wt(k-1,j,i)) * &
							! equation 13:
						   ( psi_old(k+1,j,i+1)+psi_old(k+1,j,i)- &
						     psi_old(k-1,j,i+1)-psi_old(k-1,j,i) ) / &
						   ( psi_old(k+1,j,i+1)+psi_old(k+1,j,i)+ &
						     psi_old(k-1,j,i+1)+psi_old(k-1,j,i)+small ) / &
						     ( 0.5_sp*(dzn(k-1)+dzn(k)) ) + &
						    ! repeat for y dimension:
							! equation 14:
							0.25_sp*(vt(k,j,i+1)+vt(k,j,i)+vt(k,j-1,i+1)+vt(k,j-1,i)) * &
							! equation 13:
						   ( psi_old(k,j+1,i+1)+psi_old(k,j+1,i)- &
						     psi_old(k,j-1,i+1)-psi_old(k,j-1,i) ) / &
						   ( psi_old(k,j+1,i+1)+psi_old(k,j+1,i)+ &
						     psi_old(k,j-1,i+1)+psi_old(k,j-1,i)+small ) / &
						     ( 0.5_sp*(dyn(j-1)+dyn(j)) ) )
						     
						     
						! equation 13 page 330 of smolarkiewicz (1984) 
						! journal of computational physics
						! second term of v wind:
						u_j_bar2 = 0.5_sp*dt*vt(k,j,i) * ( &
							! equation 14:
							0.25_sp*(wt(k,j+1,i)+wt(k,j,i)+wt(k-1,j+1,i)+wt(k-1,j,i)) * &
							! equation 13:
						   ( psi_old(k+1,j+1,i)+psi_old(k+1,j,i)- &
						     psi_old(k-1,j+1,i)-psi_old(k-1,j,i) ) / &
						   ( psi_old(k+1,j+1,i)+psi_old(k+1,j,i)+ &
						     psi_old(k-1,j+1,i)+psi_old(k-1,j,i)+small ) / &
						     ( 0.5_sp*(dzn(k-1)+dzn(k)) ) + &
						    ! repeat for y dimension:
							! equation 14:
							0.25_sp*(ut(k,j+1,i)+ut(k,j,i)+ut(k,j+1,i-1)+ut(k,j,i-1)) * &
							! equation 13:
						   ( psi_old(k,j+1,i+1)+psi_old(k,j,i+1)- &
						     psi_old(k,j+1,i-1)-psi_old(k,j,i-1) ) / &
						   ( psi_old(k,j+1,i+1)+psi_old(k,j,i+1)+ &
						     psi_old(k,j+1,i-1)+psi_old(k,j,i-1)+small ) / &
						     ( 0.5_sp*(dxn(i-1)+dxn(i)) ) )
						     
						! equation 13 page 330 of smolarkiewicz (1984) 
						! journal of computational physics
						! second term of w wind:
						u_j_bar3 = 0.5_sp*dt*wt(k,j,i) * ( &
							! equation 14:
							0.25_sp*(vt(k+1,j,i)+vt(k,j,i)+vt(k+1,j-1,i)+vt(k,j-1,i)) * &
							! equation 13:
						   ( psi_old(k+1,j+1,i)+psi_old(k,j+1,i)- &
						     psi_old(k+1,j-1,i)-psi_old(k,j-1,i) ) / &
						   ( psi_old(k+1,j+1,i)+psi_old(k,j+1,i)+ &
						     psi_old(k+1,j-1,i)+psi_old(k,j-1,i)+small ) / &
						     ( 0.5_sp*(dyn(j-1)+dyn(j)) ) + &
						    ! repeat for y dimension:
							! equation 14:
							0.25_sp*(ut(k+1,j,i)+ut(k,j,i)+ut(k+1,j,i-1)+ut(k,j,i-1)) * &
							! equation 13:
						   ( psi_old(k+1,j,i+1)+psi_old(k,j,i+1)- &
						     psi_old(k+1,j,i-1)-psi_old(k,j,i-1) ) / &
						   ( psi_old(k+1,j,i+1)+psi_old(k,j,i+1)+ &
						     psi_old(k+1,j,i-1)+psi_old(k,j,i-1)+small ) / &
						     ( 0.5_sp*(dxn(i-1)+dxn(i)) ) )
						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!




						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
						! last update of equation 13
						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
						! u wind:
						ut_sav(k,j,i)=(abs(ut(k,j,i))*dx(i)-dt*ut(k,j,i)*ut(k,j,i) ) * &
							(psi_old(k,j,i+1)-psi_old(k,j,i) ) / &
							(psi_old(k,j,i+1)+psi_old(k,j,i)+small) /dx(i) - u_j_bar1
						! v wind:
						vt_sav(k,j,i)=(abs(vt(k,j,i))*dy(j)-dt*vt(k,j,i)*vt(k,j,i) ) * &
							(psi_old(k,j+1,i)-psi_old(k,j,i) ) / &
							(psi_old(k,j+1,i)+psi_old(k,j,i)+small) /dy(j) - u_j_bar2														
						! w wind:
						wt_sav(k,j,i)=(abs(wt(k,j,i))*dz(k)-dt*wt(k,j,i)*wt(k,j,i) ) * &
							(psi_old(k+1,j,i)-psi_old(k,j,i) ) / &
							(psi_old(k+1,j,i)+psi_old(k,j,i)+small) /dz(k) - u_j_bar3
						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
							
						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
						! last update of eq 38 smolarkiewicz 1984
						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
						ut_sav(k,j,i)=ut_sav(k,j,i) - 0.25_sp*dt*ut(k,j,i) * &
						 ( (ut(k,j,i+1)-ut(k,j,i-1))/(0.5_sp*(dxn(i-1)+dxn(i)))-u_div1 )
						vt_sav(k,j,i)=vt_sav(k,j,i) - 0.25_sp*dt*vt(k,j,i) * &
						 ( (vt(k,j+1,i)-vt(k,j-1,i))/(0.5_sp*(dyn(j-1)+dyn(j)))-u_div2 )
						wt_sav(k,j,i)=wt_sav(k,j,i) - 0.25_sp*dt*wt(k,j,i) * &
						 ( (wt(k+1,j,i)-wt(k-1,j,i))/(0.5_sp*(dzn(k-1)+dzn(k)))-u_div3 )
						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


					enddo
				enddo
			enddo
!$omp end simd

			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			! associate pointers to targets                                              !
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			if(modulo(it2,2).eq.1) then  
										 
				ut => u_store1
				vt => v_store1
				wt => w_store1
				ut_sav => u_store2
				vt_sav => v_store2
				wt_sav => w_store2
			else if(modulo(it2,2).eq.0) then			
				ut => u_store2
				vt => v_store2
				wt => w_store2
				ut_sav => u_store1
				vt_sav => v_store1
				wt_sav => w_store1
			endif
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			call exchange_full(comm3d, id, kp, jp, ip, r_h,r_h,r_h,r_h,l_h,r_h, &
														ut,dims,coords)
			call exchange_full(comm3d, id, kp, jp, ip, r_h,r_h,l_h,r_h,r_h,r_h, &
														vt,dims,coords)
			call exchange_full(comm3d, id, kp, jp, ip, l_h,r_h,r_h,r_h,r_h,r_h, &
														wt,dims,coords)
		endif
		
		
		
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        ! Non oscillatory forward in time (NFT) flux limiter -                           !
        ! Smolarkiewicz and Grabowski (1990)                                             !
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
		if( (it > 1) .and. monotone) then
			it2=it2+1
		
		
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			! equations 20a and b of Smolarkiewicz and Grabowski (1990, JCP, 86)         !
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!$omp simd	
			do i=1,ip
				do j=1,jp
					do k=1,kp			
						! x direction - note: should the last q in the max/min be q+1?
						psi_i_max(k,j,i)=max(psi(k,j,i-1),psi(k,j,i),psi(k,j,i+1), &
									psi_old(k,j,i-1),psi_old(k,j,i),psi_old(k,j,i+1))
					
						psi_i_min(k,j,i)=min(psi(k,j,i-1),psi(k,j,i),psi(k,j,i+1), &
									psi_old(k,j,i-1),psi_old(k,j,i),psi_old(k,j,i+1))
					enddo
				enddo
			enddo
!$omp end simd

!$omp simd	
			do i=1,ip
				do j=1,jp
					do k=1,kp			
						! y direction - note: should the last q in the max/min be q+1?
						psi_j_max(k,j,i)=max(psi(k,j-1,i),psi(k,j,i),psi(k,j+1,i), &
									psi_old(k,j-1,i),psi_old(k,j,i),psi_old(k,j+1,i))
					
						psi_j_min(k,j,i)=min(psi(k,j-1,i),psi(k,j,i),psi(k,j+1,i), &
									psi_old(k,j-1,i),psi_old(k,j,i),psi_old(k,j+1,i))
					enddo
				enddo
			enddo
!$omp end simd

!$omp simd	
			do i=1,ip
				do j=1,jp
					do k=1,kp			
						! z direction - note: should the last q in the max/min be q+1?
						psi_k_max(k,j,i)=max(psi(k-1,j,i),psi(k,j,i),psi(k+1,j,i), &
									psi_old(k-1,j,i),psi_old(k,j,i),psi_old(k+1,j,i))
					
						psi_k_min(k,j,i)=min(psi(k-1,j,i),psi(k,j,i),psi(k+1,j,i), &
									psi_old(k-1,j,i),psi_old(k,j,i),psi_old(k+1,j,i))
					enddo
				enddo
			enddo
!$omp end simd
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!





			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			! Equations 19a and b of Smolarkiewicz and Grabowski (1990, JCP)             !
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!$omp simd	
			do i=1,ip
				do j=1,jp
					do k=1,kp		
						denom1=(dt*((max(ut(k,j,i-1),0._sp)*psi_old(k,j,i-1)- &
								  min(ut(k,j,i),0._sp)*psi_old(k,j,i+1))/dxn(i-1)+ &
							    (max(vt(k,j-1,i),0._sp)*psi_old(k,j-1,i)-&
								  min(vt(k,j,i),0._sp)*psi_old(k,j+1,i))/dyn(j-1) + &
							    (max(wt(k-1,j,i),0._sp)*psi_old(k-1,j,i)-&
								  min(wt(k,j,i),0._sp)*psi_old(k+1,j,i))/dzn(k-1) &
								  +small))
								  
						denom2=(dt*((max(ut(k,j,i),0._sp)*psi_old(k,j,i)- &
							      min(ut(k,j,i-1),0._sp)*psi_old(k,j,i))/dxn(i-1) + &
								(max(vt(k,j,i),0._sp)*psi_old(k,j,i)-&
								  min(vt(k,j-1,i),0._sp)*psi_old(k,j,i))/dyn(j-1) + &
								(max(wt(k,j,i),0._sp)*psi_old(k,j,i)-&
								  min(wt(k-1,j,i),0._sp)*psi_old(k,j,i))/dzn(k-1) &
								  +small))
								  
						beta_i_up(k,j,i)=(psi_i_max(k,j,i)-psi_old(k,j,i)) / denom1
							
								  
						beta_i_down(k,j,i)=(psi_old(k,j,i)-psi_i_min(k,j,i)) / denom2
											

						beta_j_up(k,j,i)=(psi_j_max(k,j,i)-psi_old(k,j,i)) / denom1
								  
						beta_j_down(k,j,i)=(psi_old(k,j,i)-psi_j_min(k,j,i)) / denom2

						beta_k_up(k,j,i)=(psi_k_max(k,j,i)-psi_old(k,j,i)) / denom1
								  
						beta_k_down(k,j,i)=(psi_old(k,j,i)-psi_k_min(k,j,i)) / denom2
					enddo
				enddo
			enddo 
!$omp end simd
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!



			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			! exchange halos for beta_i_up, down
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			call exchange_along_dim(comm3d, id, kp, jp, ip, r_h,r_h,r_h,r_h,r_h,r_h, &
														beta_i_up,dims,coords)
			call exchange_along_dim(comm3d, id, kp, jp, ip, r_h,r_h,r_h,r_h,r_h,r_h, &
														beta_i_down,dims,coords)
			call exchange_along_dim(comm3d, id, kp, jp, ip, r_h,r_h,r_h,r_h,r_h,r_h, &
														beta_j_up,dims,coords)
			call exchange_along_dim(comm3d, id, kp, jp, ip, r_h,r_h,r_h,r_h,r_h,r_h, &
														beta_j_down,dims,coords)
			call exchange_along_dim(comm3d, id, kp, jp, ip, r_h,r_h,r_h,r_h,r_h,r_h, &
														beta_k_up,dims,coords)
			call exchange_along_dim(comm3d, id, kp, jp, ip, r_h,r_h,r_h,r_h,r_h,r_h, &
														beta_k_down,dims,coords)
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

								
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			! equation 18 of Smolarkiewicz and Grabowski (1990, JCP, 86)                 !
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!$omp simd	
			do i=1,ip
				do j=1,jp
					do k=1,kp			
						ut_sav(k,j,i)=min(1._sp,beta_i_down(k,j,i), &
										 beta_i_up(k,j,i+1))*max(ut(k,j,i),0._sp) + &
									  min(1._sp,beta_i_up(k,j,i), &
									     beta_i_down(k,j,i+1))*min(ut(k,j,i),0._sp)
						vt_sav(k,j,i)=min(1._sp,beta_j_down(k,j,i), &
										 beta_j_up(k,j+1,i))*max(vt(k,j,i),0._sp) + &
									  min(1._sp,beta_j_up(k,j,i), &
									     beta_j_down(k,j+1,i))*min(vt(k,j,i),0._sp)
						wt_sav(k,j,i)=min(1._sp,beta_k_down(k,j,i), &
										 beta_k_up(k+1,j,i))*max(wt(k,j,i),0._sp) + &
									  min(1._sp,beta_k_up(k,j,i), &
									     beta_k_down(k+1,j,i))*min(wt(k,j,i),0._sp)
					enddo
				enddo
			enddo 
!$omp end simd
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			! associate pointers to targets                                              !
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			ut => u_store2
			vt => v_store2
			wt => w_store2
			ut_sav => u_store1
			vt_sav => v_store1
			wt_sav => w_store1
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			call exchange_full(comm3d, id, kp, jp, ip, r_h,r_h,r_h,r_h,l_h,r_h, &
														ut,dims,coords)
			call exchange_full(comm3d, id, kp, jp, ip, r_h,r_h,l_h,r_h,r_h,r_h, &
														vt,dims,coords)
			call exchange_full(comm3d, id, kp, jp, ip, l_h,r_h,r_h,r_h,r_h,r_h, &
														wt,dims,coords)

		endif
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!




		!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
		! advect using first order upwind                                                !
		!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
		do n=1,nq
            call first_order_upstream_3d(dt,dx,dy,dz,rhoa,&
                    ip,jp,kp,l_h,r_h,ut,vt,wt,psi_in(:,:,:,n))
        enddo
		!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


		
		if((it <= kord) .and. (kord >= 1)) then
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			! set halos																	 !
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!		
			call exchange_full(comm3d, id, kp, jp, ip, r_h,r_h,r_h,r_h,r_h,r_h, &
									psi_old,dims,coords)
			!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!			
		endif		
 	enddo
 

	! no dangling pointers
	if (associated(ut) ) nullify(ut)
	if (associated(vt) ) nullify(vt)
	if (associated(wt) ) nullify(wt)
	if (associated(ut_sav) ) nullify(ut_sav)
	if (associated(vt_sav) ) nullify(vt_sav)
	if (associated(wt_sav) ) nullify(wt_sav)
	if (associated(psi) ) nullify(psi)
	if (associated(psi_old) ) nullify(psi_old)

    do n=1,nq
    	psi_in(:,:,:,n)=psi_in(:,:,:,n)+minglobal(n)
    enddo
	end subroutine mpdata_vec_3d
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


    end module advection_s_3d
