!==================================================================================================================================
! Copyright (c) 2016 - 2017 Gregor Gassner
! Copyright (c) 2016 - 2017 Florian Hindenlang
! Copyright (c) 2016 - 2017 Andrew Winters
!
! This file is part of FLUXO (github.com/project-fluxo/fluxo). FLUXO is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3
! of the License, or (at your option) any later version.
!
! FLUXO is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
! of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License v3.0 for more details.
!
! You should have received a copy of the GNU General Public License along with FLUXO. If not, see <http://www.gnu.org/licenses/>.
!==================================================================================================================================
#include "defines.h"

!==================================================================================================================================
!> Routines to compute two-point average fluxes for the volint when using the split-form (DiscType=2)
!==================================================================================================================================
MODULE MOD_Flux_Average
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE
!----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES 
!----------------------------------------------------------------------------------------------------------------------------------
! Private Part --------------------------------------------------------------------------------------------------------------------
! Public Part ---------------------------------------------------------------------------------------------------------------------

INTERFACE EvalEulerFluxTilde3D
  MODULE PROCEDURE EvalEulerFluxTilde3D
END INTERFACE

INTERFACE EvalUaux
  MODULE PROCEDURE EvalUaux
END INTERFACE

INTERFACE StandardDGFlux
  MODULE PROCEDURE StandardDGFlux
END INTERFACE

INTERFACE StandardDGFluxVec
  MODULE PROCEDURE StandardDGFluxVec
END INTERFACE

INTERFACE StandardDGFluxDealiasedMetricVec
  MODULE PROCEDURE StandardDGFluxDealiasedMetricVec
END INTERFACE


PUBLIC::EvalEulerFluxTilde3D
PUBLIC::EvalUaux
PUBLIC::StandardDGFlux
PUBLIC::StandardDGFluxVec
PUBLIC::StandardDGFluxDealiasedMetricVec
!==================================================================================================================================

CONTAINS


!==================================================================================================================================
!> Compute MHD transformed fluxes using conservative variables and derivatives for every volume Gauss point.
!> directly apply metrics and output the tranformed flux 
!==================================================================================================================================
SUBROUTINE EvalEulerFluxTilde3D(iElem,ftilde,gtilde,htilde,Uaux)
! MODULES
USE MOD_PreProc
USE MOD_DG_Vars,ONLY:U
USE MOD_Equation_Vars ,ONLY:kappaM1,kappaM2,smu_0,s2mu_0
USE MOD_Mesh_Vars     ,ONLY:Metrics_fTilde,Metrics_gTilde,Metrics_hTilde
#ifdef PP_GLM
USE MOD_Equation_vars ,ONLY:GLM_ch
#endif /*PP_GLM*/
#ifdef OPTIMIZED
USE MOD_DG_Vars       ,ONLY:nTotal_vol
#endif /*OPTIMIZED*/
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER,INTENT(IN)                        :: iElem !< current element index in volint
!----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,DIMENSION(1:PP_nVar,0:PP_N,0:PP_N,0:PP_N),INTENT(OUT) :: ftilde !< transformed flux f(iVar,i,j,k)
REAL,DIMENSION(1:PP_nVar,0:PP_N,0:PP_N,0:PP_N),INTENT(OUT) :: gtilde !< transformed flux g(iVar,i,j,k)
REAL,DIMENSION(1:PP_nVar,0:PP_N,0:PP_N,0:PP_N),INTENT(OUT) :: htilde !< transformed flux h(iVar,i,j,k)
REAL,DIMENSION(8,0:PP_N,0:PP_N,0:PP_N),INTENT(OUT) :: Uaux           !< auxiliary variables:(srho,v1,v2,v3,p_t,|v|^2,|B|^2,v*b)
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL,DIMENSION(1:PP_nVar) :: f,g,h                             ! Cartesian fluxes (iVar)
REAL                :: srho                                    ! reciprocal values for density and the value of specific energy
REAL                :: v1,v2,v3,v_2,p                          ! velocity and pressure(including magnetic pressure
REAL                :: bb2,vb                                  ! magnetic field, bb2=|bvec|^2, v dot b
REAL                :: Ep                                      ! E + p
INTEGER             :: i 
#ifndef OPTIMIZED
INTEGER             :: j,k
#endif
#ifdef CARTESIANFLUX 
REAL                :: X_xi,Y_eta,Z_zeta
#endif 
!==================================================================================================================================
#ifdef CARTESIANFLUX 
X_xi   = Metrics_fTilde(1,0,0,0,iElem)
Y_eta  = Metrics_gTilde(2,0,0,0,iElem)
Z_zeta = Metrics_hTilde(3,0,0,0,iElem)
#endif 
#ifdef OPTIMIZED
DO i=0,nTotal_vol-1
#else /*OPTIMIZED*/
DO k=0,PP_N;  DO j=0,PP_N; DO i=0,PP_N
#endif /*OPTIMIZED*/
  ASSOCIATE(rho   =>U(1,PP_IJK,iElem), &
            rhov1 =>U(2,PP_IJK,iElem), &
            rhov2 =>U(3,PP_IJK,iElem), &
            rhov3 =>U(4,PP_IJK,iElem), &
            Etotal=>U(5,PP_IJK,iElem), &
            b1    =>U(6,PP_IJK,iElem), &
            b2    =>U(7,PP_IJK,iElem), &
            b3    =>U(8,PP_IJK,iElem)  )
  ! auxiliary variables
  srho = 1. / rho ! 1/rho
  v1   = rhov1*srho 
  v2   = rhov2*srho 
  v3   = rhov3*srho 
  v_2  = v1*v1+v2*v2+v3*v3 
  bb2  = (b1*b1+b2*b2+b3*b3)
  vb   = (b1*v1+b2*v2+b3*v3)
  !p = ptilde (includes magnetic pressure)
  p    = kappaM1*(Etotal-0.5*rho*(v_2))-KappaM2*s2mu_0*bb2
  Ep   = (Etotal + p)
  
  Uaux(:,PP_IJK)=(/srho,v1,v2,v3,p,v_2,bb2,vb/)
  ! Advection part
  ! Advection fluxes x-direction
  f(1)=rhov1                     ! rho*u
  f(2)=rhov1*v1+p  -smu_0*b1*b1  ! rho*u²+p     -1/mu_0*b1*b1
  f(3)=rhov1*v2    -smu_0*b1*b2  ! rho*u*v      -1/mu_0*b1*b2
  f(4)=rhov1*v3    -smu_0*b1*b3  ! rho*u*w      -1/mu_0*b1*b3
  f(5)=Ep*v1       -smu_0*b1*vb  ! (rho*e+p)*u  -1/mu_0*b1*(v dot B)
  f(6)=0.
  f(7)=v1*b2-b1*v2
  f(8)=v1*b3-b1*v3
  ! Advection fluxes y-direction
  g(1)=rhov2                     ! rho*v      
  g(2)=f(3)                      ! rho*u*v      -1/mu_0*b2*b1
  g(3)=rhov2*v2+p  -smu_0*b2*b2  ! rho*v²+p     -1/mu_0*b2*b2
  g(4)=rhov2*v3    -smu_0*b2*b3  ! rho*v*w      -1/mu_0*b2*b3
  g(5)=Ep*v2       -smu_0*b2*vb  ! (rho*e+p)*v  -1/mu_0*b2*(v dot B)
  g(6)=-f(7)                     ! (v2*b1-b2*v1)
  g(7)=0.
  g(8)=v2*b3-b2*v3
  ! Advection fluxes z-direction
  h(1)=rhov3                     ! rho*v
  h(2)=f(4)                      ! rho*u*w      -1/mu_0*b3*b1
  h(3)=g(4)                      ! rho*v*w      -1/mu_0*b3*b2
  h(4)=rhov3*v3+p  -smu_0*b3*b3  ! rho*v²+p     -1/mu_0*b3*b3
  h(5)=Ep*v3       -smu_0*b3*vb  ! (rho*e+p)*w  -1/mu_0*b3*(v dot B)
  h(6)=-f(8)                     ! v3*b1-b3*v1 
  h(7)=-g(8)                     ! v3*b2-b3*v2
  h(8)=0.

#ifdef PP_GLM
  f(6) = f(6)+GLM_ch*U(9,PP_IJK,iElem)
  f(9) = GLM_ch*b1

  g(7) = g(7)+GLM_ch*U(9,PP_IJK,iElem)
  g(9) = GLM_ch*b2

  h(8) = h(8)+GLM_ch*U(9,PP_IJK,iElem)
  h(9) = GLM_ch*b3
#endif /* PP_GLM */

END ASSOCIATE ! rho,rhov1,rhov2,rhov3,Etotal,b1,b2,b3

  !now transform fluxes to reference ftilde,gtilde,htilde
#ifdef CARTESIANFLUX
  !for cartesian meshes, metric tensor is constant and diagonal:
  ftilde(:,PP_IJK) =  f(:)*X_xi
  gtilde(:,PP_IJK) =  g(:)*Y_eta
  htilde(:,PP_IJK) =  h(:)*Z_zeta
#else /* CURVED FLUX*/
  ! general curved metrics
  ftilde(:,PP_IJK) =   f(:)*Metrics_fTilde(1,PP_IJK,iElem)  &
                     + g(:)*Metrics_fTilde(2,PP_IJK,iElem)  &
                     + h(:)*Metrics_fTilde(3,PP_IJK,iElem)
  gtilde(:,PP_IJK) =   f(:)*Metrics_gTilde(1,PP_IJK,iElem)  &
                     + g(:)*Metrics_gTilde(2,PP_IJK,iElem)  &
                     + h(:)*Metrics_gTilde(3,PP_IJK,iElem)
  htilde(:,PP_IJK) =   f(:)*Metrics_hTilde(1,PP_IJK,iElem)  &
                     + g(:)*Metrics_hTilde(2,PP_IJK,iElem)  &
                     + h(:)*Metrics_hTilde(3,PP_IJK,iElem)
#endif /*CARTESIANFLUX*/
#ifdef OPTIMIZED
END DO ! i
#else /*OPTIMIZED*/
END DO; END DO; END DO ! i,j,k
#endif /*OPTIMIZED*/
END SUBROUTINE EvalEulerFluxTilde3D



!==================================================================================================================================
!> computes auxiliary nodal variables (1/rho,v_1,v_2,v_3,p_t,|v|^2) 
!==================================================================================================================================
SUBROUTINE EvalUaux(iElem,Uaux)
! MODULES
USE MOD_PreProc
USE MOD_DG_Vars       ,ONLY:U
USE MOD_Equation_Vars ,ONLY:nAuxVar
USE MOD_Equation_Vars ,ONLY:kappaM1,KappaM2,s2mu_0
#ifdef OPTIMIZED
USE MOD_DG_Vars,ONLY:nTotal_vol
#endif /*OPTIMIZED*/
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER,INTENT(IN)                        :: iElem !< current element index in volint
!----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,DIMENSION(nAuxVar,0:PP_N,0:PP_N,0:PP_N),INTENT(OUT) :: Uaux   !< auxiliary variables:(srho,v1,v2,v3,p_t,|v|^2,|B|^2,v*b
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER             :: i 
#ifndef OPTIMIZED
INTEGER             :: j,k
#endif
!==================================================================================================================================
#ifdef OPTIMIZED
DO i=0,nTotal_vol-1
#else /*OPTIMIZED*/
DO k=0,PP_N;  DO j=0,PP_N; DO i=0,PP_N
#endif /*OPTIMIZED*/
  ! auxiliary variables
  Uaux(1  ,PP_IJK) = 1./U(1,PP_IJK,iElem)                      ! 1/rho
  Uaux(2:4,PP_IJK) = Uaux(1,PP_IJK)*U(2:4,PP_IJK,iElem)        ! vec{rho*v}/rho
  Uaux(6  ,PP_IJK) = SUM(Uaux(2:4,PP_IJK)*Uaux(2:4,PP_IJK))                  ! |v|^2
  Uaux(7  ,PP_IJK)  =SUM(U(6:8,PP_IJK,iElem)**2)               ! |B|^2
  Uaux(8  ,PP_IJK)  =SUM(Uaux(2:4,PP_IJK)*U(6:8,PP_IJK,iElem)) ! v*B
  !total pressure=gas pressure + magnetic pressure
  Uaux(5  ,PP_IJK)=kappaM1*(U(5,PP_IJK,iElem)-0.5*U(1,PP_IJK,iElem)*Uaux(6,PP_IJK))-kappaM2*s2mu_0*Uaux(7,PP_IJK) !p_t 
#ifdef OPTIMIZED
END DO ! i
#else /*OPTIMIZED*/
END DO; END DO; END DO ! i,j,k
#endif /*OPTIMIZED*/
END SUBROUTINE EvalUaux


!==================================================================================================================================
!> Computes the standard flux in x-direction for the hyperbolic part ( normally used with a rotated state)
!==================================================================================================================================
SUBROUTINE StandardDGFlux(Fstar,UL,UR)
! MODULES
USE MOD_PreProc
USE MOD_Equation_Vars,ONLY:kappaM1,kappaM2,smu_0,s2mu_0
#ifdef PP_GLM
USE MOD_Equation_Vars,ONLY:GLM_ch
#endif
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,DIMENSION(PP_nVar),INTENT(IN)  :: UL !< left state
REAL,DIMENSION(PP_nVar),INTENT(IN)  :: UR !< right state
!----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,DIMENSION(PP_nVar),INTENT(OUT) :: Fstar !< 1D flux in x direction
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                                :: rhoqL,rhoqR
REAL                                :: sRho_L,sRho_R,v1_L,v2_L,v3_L,v1_R,v2_R,v3_R,bb2_L,bb2_R,vb_L,vb_R,p_L,p_R
!==================================================================================================================================
! Get the inverse density, velocity, and pressure on left and right
ASSOCIATE(  rho_L =>UL(1),  rho_R =>UR(1), &
           rhoU_L =>UL(2), rhoU_R =>UR(2), &
           rhoV_L =>UL(3), rhoV_R =>UR(3), &
           rhoW_L =>UL(4), rhoW_R =>UR(4), &
           rhoE_L =>UL(5), rhoE_R =>UR(5), &
             b1_L =>UL(6),   b1_R =>UR(6), &
             b2_L =>UL(7),   b2_R =>UR(7), &
             b3_L =>UL(8),   b3_R =>UR(8)  )
sRho_L = 1./rho_L
sRho_R = 1./rho_R
v1_L = sRho_L*rhoU_L;  v2_L = sRho_L*rhoV_L ; v3_L = sRho_L*rhoW_L
v1_R = sRho_R*rhoU_R;  v2_R = sRho_R*rhoV_R ; v3_R = sRho_R*rhoW_R
bb2_L  = (b1_L*b1_L+b2_L*b2_L+b3_L*b3_L)
bb2_R  = (b1_R*b1_R+b2_R*b2_R+b3_R*b3_R)

p_L    = (kappaM1)*(rhoE_L - 0.5*(rhoU_L*v1_L + rhoV_L*v2_L + rhoW_L*v3_L))-kappaM2*s2mu_0*bb2_L
p_R    = (kappaM1)*(rhoE_R - 0.5*(rhoU_R*v1_R + rhoV_R*v2_R + rhoW_R*v3_R))-kappaM2*s2mu_0*bb2_R

vb_L  = v1_L*b1_L+v2_L*b2_L+v3_L*b3_L
vb_R  = v1_R*b1_R+v2_R*b2_R+v3_R*b3_R
  
! Standard DG flux
rhoqL    = rho_L*v1_L
rhoqR    = rho_R*v1_R
Fstar(1) = 0.5*(rhoqL      + rhoqR)
Fstar(2) = 0.5*(rhoqL*v1_L + rhoqR*v1_R +(p_L + p_R)-smu_0*(b1_L*b1_L+b1_R*b1_R))
Fstar(3) = 0.5*(rhoqL*v2_L + rhoqR*v2_R             -smu_0*(b2_L*b2_L+b2_R*b2_R))
Fstar(4) = 0.5*(rhoqL*v3_L + rhoqR*v3_R             -smu_0*(b3_L*b3_L+b3_R*b3_R))
Fstar(5) = 0.5*((rhoE_L + p_L)*v1_L + (rhoE_R + p_R)*v1_R- smu_0*(b1_L*vb_L+b1_R*vb_R))
Fstar(6) = 0.
Fstar(7) = 0.5*(v1_L*b2_L-b1_L*v2_L + v1_R*b2_R-b1_R*v2_R)
Fstar(8) = 0.5*(v1_L*b3_L-b1_L*v3_L + v1_R*b3_R-b1_R*v3_R)
#ifdef PP_GLM
Fstar(5) = Fstar(5)+0.5*GLM_ch*(b1_L*UL(9)+b1_R*UR(9))
Fstar(6) = Fstar(6)+0.5*GLM_ch*(     UL(9)+     UR(9))
Fstar(9) =          0.5*GLM_ch*(b1_L      +b1_R      )
#endif /* PP_GLM */
END ASSOCIATE !rho_L/R,rhov1_L/R,...
END SUBROUTINE StandardDGFlux


!==================================================================================================================================
!> Computes the standard DG flux transformed with the metrics (fstar=f*metric1+g*metric2+h*metric3 ) for the advection
!> part of the MHD equations
!> for curved metrics, no dealiasing is done (exactly = standard DG )!
!==================================================================================================================================
SUBROUTINE StandardDGFluxVec(UL,UR,UauxL,UauxR, &
#ifdef CARTESIANFLUX
                             metric, &
#else
                             metric_L,metric_R, &
#endif
                             Fstar)
! MODULES
USE MOD_PreProc
USE MOD_Equation_Vars,ONLY:smu_0
#ifdef PP_GLM
USE MOD_Equation_vars ,ONLY:GLM_ch
#endif /*PP_GLM*/
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,DIMENSION(PP_nVar),INTENT(IN)  :: UL             !< left state
REAL,DIMENSION(PP_nVar),INTENT(IN)  :: UR             !< right state
REAL,DIMENSION(8),INTENT(IN)        :: UauxL          !< left auxiliary variables
REAL,DIMENSION(8),INTENT(IN)        :: UauxR          !< right auxiliary variables
#ifdef CARTESIANFLUX
REAL,INTENT(IN)                     :: metric(3)      !< single metric (for CARTESIANFLUX=T)
#else
REAL,INTENT(IN)                     :: metric_L(3)    !< left metric
REAL,INTENT(IN)                     :: metric_R(3)    !< right metric
#endif
!----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,DIMENSION(PP_nVar),INTENT(OUT) :: Fstar   !< transformed central flux
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                                :: qv_L,qv_R,qb_L,qb_R
#ifdef CARTESIANFLUX
REAL                                :: metric_L(3)
REAL                                :: metric_R(3)
!==================================================================================================================================
metric_L=metric
metric_R=metric ! no optimization for cartesian flux here!
#endif /*CARTESIANFLUX*/

! Get the inverse density, velocity, and pressure on left and right
ASSOCIATE(  rho_L =>   UL(1),  rho_R =>   UR(1), &
           rhoU_L =>   UL(2), rhoU_R =>   UR(2), &
           rhoV_L =>   UL(3), rhoV_R =>   UR(3), &
           rhoW_L =>   UL(4), rhoW_R =>   UR(4), &
           rhoE_L =>   UL(5), rhoE_R =>   UR(5), &
             b1_L =>   UL(6),   b1_R =>   UR(6), &
             b2_L =>   UL(7),   b2_R =>   UR(7), &
             b3_L =>   UL(8),   b3_R =>   UR(8), &
          !srho_L =>UauxL(1), srho_R =>UauxR(1), &
             v1_L =>UauxL(2),   v1_R =>UauxR(2), &
             v2_L =>UauxL(3),   v2_R =>UauxR(3), &
             v3_L =>UauxL(4),   v3_R =>UauxR(4), &
             pt_L =>UauxL(5),   pt_R =>UauxR(5), & !total pressure = gas pressure+magnetic pressure
           !vv2_L =>UauxL(6),  vv2_R =>UauxR(6), &
           !bb2_L =>UauxL(7),  bb2_R =>UauxR(7), &
             vb_L =>UauxL(8),   vb_R =>UauxR(8)  )

!without metric dealiasing (=standard DG weak form on curved meshes)
qv_L = v1_L*metric_L(1) + v2_L*metric_L(2) + v3_L*metric_L(3)
qb_L = b1_L*metric_L(1) + b2_L*metric_L(2) + b3_L*metric_L(3)

qv_R = v1_R*metric_R(1) + v2_R*metric_R(2) + v3_R*metric_R(3)
qb_R = b1_R*metric_R(1) + b2_R*metric_R(2) + b3_R*metric_R(3)

! Standard DG flux
!without metric dealiasing (=standard DG weak form on curved meshes)
Fstar(1) = 0.5*( rho_L*qv_L +  rho_R*qv_R )
Fstar(2) = 0.5*(rhoU_L*qv_L + rhoU_R*qv_R + metric_L(1)*pt_L+metric_R(1)*pt_R -smu_0*(qb_L*b1_L+qb_R*b1_R) )
Fstar(3) = 0.5*(rhoV_L*qv_L + rhoV_R*qv_R + metric_L(2)*pt_L+metric_R(2)*pt_R -smu_0*(qb_L*b2_L+qb_R*b2_R) )
Fstar(4) = 0.5*(rhoW_L*qv_L + rhoW_R*qv_R + metric_L(3)*pt_L+metric_R(3)*pt_R -smu_0*(qb_L*b3_L+qb_R*b3_R) )
Fstar(5) = 0.5*((rhoE_L + pt_L)*qv_L  + (rhoE_R + pt_R)*qv_R      -smu_0*(qb_L*vb_L+qb_R*vb_R) )
Fstar(6) = 0.5*(qv_L*b1_L-qb_L*v1_L + qv_R*b1_R-qb_R*v1_R)
Fstar(7) = 0.5*(qv_L*b2_L-qb_L*v2_L + qv_R*b2_R-qb_R*v2_R)
Fstar(8) = 0.5*(qv_L*b3_L-qb_L*v3_L + qv_R*b3_R-qb_R*v3_R)

#ifdef PP_GLM
!without metric dealiasing (=standard DG weak form on curved meshes)
Fstar(5) = Fstar(5) + 0.5*GLM_ch*(qb_L*UL(9)             + qb_R*UR(9))
Fstar(6) = Fstar(6) + 0.5*GLM_ch*(     UL(9)*metric_L(1) +      UR(9)*metric_R(1))
Fstar(7) = Fstar(7) + 0.5*GLM_ch*(     UL(9)*metric_L(2) +      UR(9)*metric_R(2))
Fstar(8) = Fstar(8) + 0.5*GLM_ch*(     UL(9)*metric_L(3) +      UR(9)*metric_R(3))
Fstar(9) =            0.5*GLM_ch*(qb_L                   +qb_R                   )

#endif /* PP_GLM */

END ASSOCIATE !rho_L/R,rhov1_L/R,...
END SUBROUTINE StandardDGFluxVec


!==================================================================================================================================
!> Computes the standard DG flux transformed with the metrics (fstar=f*metric1+g*metric2+h*metric3 ) for the advection
!> part of the MHD equations
!> for curved metrics, 1/2(metric_L+metric_R) is taken!
!==================================================================================================================================
SUBROUTINE StandardDGFluxDealiasedMetricVec(UL,UR,UauxL,UauxR, &
#ifdef CARTESIANFLUX
                             metric, &
#else
                             metric_L,metric_R, &
#endif
                             Fstar)
! MODULES
USE MOD_PreProc
USE MOD_Equation_Vars,ONLY:smu_0
#ifdef PP_GLM
USE MOD_Equation_vars ,ONLY:GLM_ch
#endif /*PP_GLM*/
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,DIMENSION(PP_nVar),INTENT(IN)  :: UL             !< left state
REAL,DIMENSION(PP_nVar),INTENT(IN)  :: UR             !< right state
REAL,DIMENSION(8),INTENT(IN)        :: UauxL          !< left auxiliary variables
REAL,DIMENSION(8),INTENT(IN)        :: UauxR          !< right auxiliary variables
#ifdef CARTESIANFLUX
REAL,INTENT(IN)                     :: metric(3)      !< single metric (for CARTESIANFLUX=T)
#else
REAL,INTENT(IN)                     :: metric_L(3)    !< left metric
REAL,INTENT(IN)                     :: metric_R(3)    !< right metric
#endif
!----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,DIMENSION(PP_nVar),INTENT(OUT) :: Fstar   !< transformed central flux
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                                :: qv_L,qv_R,qb_L,qb_R
#ifdef PP_GLM
REAL                                :: phiHat
#endif /*PP_GLM*/
#ifndef CARTESIANFLUX
REAL                                :: metric(3)
!==================================================================================================================================
metric = 0.5*(metric_L+metric_R)
#endif /*ndef CARTESIANFLUX*/

! Get the inverse density, velocity, and pressure on left and right
ASSOCIATE(  rho_L =>   UL(1),  rho_R =>   UR(1), &
           rhoU_L =>   UL(2), rhoU_R =>   UR(2), &
           rhoV_L =>   UL(3), rhoV_R =>   UR(3), &
           rhoW_L =>   UL(4), rhoW_R =>   UR(4), &
           rhoE_L =>   UL(5), rhoE_R =>   UR(5), &
             b1_L =>   UL(6),   b1_R =>   UR(6), &
             b2_L =>   UL(7),   b2_R =>   UR(7), &
             b3_L =>   UL(8),   b3_R =>   UR(8), &
          !srho_L =>UauxL(1), srho_R =>UauxR(1), &
             v1_L =>UauxL(2),   v1_R =>UauxR(2), &
             v2_L =>UauxL(3),   v2_R =>UauxR(3), &
             v3_L =>UauxL(4),   v3_R =>UauxR(4), &
             pt_L =>UauxL(5),   pt_R =>UauxR(5), & !total pressure = gas pressure+magnetic pressure
           !vv2_L =>UauxL(6),  vv2_R =>UauxR(6), &
           !bb2_L =>UauxL(7),  bb2_R =>UauxR(7), &
             vb_L =>UauxL(8),   vb_R =>UauxR(8)  )

qv_L = v1_L*metric(1) + v2_L*metric(2) + v3_L*metric(3)
qb_L = b1_L*metric(1) + b2_L*metric(2) + b3_L*metric(3)

qv_R = v1_R*metric(1) + v2_R*metric(2) + v3_R*metric(3)
qb_R = b1_R*metric(1) + b2_R*metric(2) + b3_R*metric(3)

! Standard DG flux
Fstar(1) = 0.5*( rho_L*qv_L +  rho_R*qv_R )
Fstar(2) = 0.5*(rhoU_L*qv_L + rhoU_R*qv_R + metric(1)*(pt_L+pt_R) -smu_0*(qb_L*b1_L+qb_R*b1_R) )
Fstar(3) = 0.5*(rhoV_L*qv_L + rhoV_R*qv_R + metric(2)*(pt_L+pt_R) -smu_0*(qb_L*b2_L+qb_R*b2_R) )
Fstar(4) = 0.5*(rhoW_L*qv_L + rhoW_R*qv_R + metric(3)*(pt_L+pt_R) -smu_0*(qb_L*b3_L+qb_R*b3_R) )
Fstar(5) = 0.5*((rhoE_L + pt_L)*qv_L  + (rhoE_R + pt_R)*qv_R      -smu_0*(qb_L*vb_L+qb_R*vb_R) )
Fstar(6) = 0.5*(qv_L*b1_L-qb_L*v1_L + qv_R*b1_R-qb_R*v1_R)
Fstar(7) = 0.5*(qv_L*b2_L-qb_L*v2_L + qv_R*b2_R-qb_R*v2_R)
Fstar(8) = 0.5*(qv_L*b3_L-qb_L*v3_L + qv_R*b3_R-qb_R*v3_R)

#ifdef PP_GLM
Fstar(5) = Fstar(5) + 0.5*GLM_ch*(qb_L*UL(9)+qb_R*UR(9))
phiHat   = 0.5*GLM_ch*(UL(9)+UR(9))
Fstar(6) = Fstar(6) + phiHat*metric(1)
Fstar(7) = Fstar(7) + phiHat*metric(2)
Fstar(8) = Fstar(8) + phiHat*metric(3)
Fstar(9) =            0.5*GLM_ch*(qb_L+qb_R)
#endif /* PP_GLM */

END ASSOCIATE !rho_L/R,rhov1_L/R,...
END SUBROUTINE StandardDGFluxDealiasedMetricVec


END MODULE MOD_Flux_Average
