module Green_function
  !! Module containing Green's function related procedures.

  use params, only: k8, dp, twopi, pi, oneI
  use electron_module, only: electron
  use phonon_module, only: phonon
  use delta, only: delta_fn_tetra, real_tetra
  use misc, only: exit_with_message, distribute_points, expi, demux_state, invert
  
  implicit none

  private
  public calculate_retarded_phonon_D0
  
contains
  
  complex(dp) function resolvent(species, ib, iwv, sampling_point)
    !! Calculate the resolvant
    !!   electron: 1/[z - E(k)], lim z -> E + i0^{+}.
    !!   phonon:   1/[z - omega^2(q)], lim z -> omega^2 + i0^{+}.
    !!
    !! species Object of particle type
    !! ib, iwv Band, wave vector indices
    !! sampling_point Sampling energy (or energy squared) in eV (or eV^2), depending on particle type.

    class(*), intent(in) :: species
    integer(k8), intent(in) :: ib, iwv
    real(dp), intent(in) :: sampling_point

    !Local variables
    real(dp) :: Im_resolvent, Re_resolvent

    select type(species)
    class is(phonon)
       !Imaginary part of resolvent
       Im_resolvent = -pi*delta_fn_tetra(sampling_point, iwv, ib, species%wvmesh, species%tetramap, &
            species%tetracount, species%tetra_squared_evals)

       !Real part of resolvent
       Re_resolvent = real_tetra(sampling_point, iwv, ib, species%wvmesh, species%tetramap, &
            species%tetracount, species%tetra_squared_evals)
    class is(electron)
       !Imaginary part of resolvent
       Im_resolvent = -pi*delta_fn_tetra(sampling_point, iwv, ib, species%wvmesh, species%tetramap, &
            species%tetracount, species%tetra_evals)

       !Real part of resolvent
       Re_resolvent = real_tetra(sampling_point, iwv, ib, species%wvmesh, species%tetramap, &
            species%tetracount, species%tetra_evals)
    class default
       call exit_with_message(&
            "Unknown particle species in resolvent. Exiting.")
    end select

    resolvent = Re_resolvent + oneI*Im_resolvent
  end function resolvent

  !subroutine calculate_retarded_phonon_D0(ph, def)
  subroutine calculate_retarded_phonon_D0(ph, def_numcells, def_supercell_atompos, pcell_equiv_atom_label)
    !! Parallel driver of the retarded, bare phonon Green's function, D0, over
    !! the IBZ states.
    !!
    !! TODO Description of the subroutine
    !!

    type(phonon), intent(in) :: ph
    !type(defect), intent(inout) :: def !TODO have to define this
    integer(k8), intent(in) :: def_numcells
    integer(k8), intent(in) :: def_supercell_atompos(def_numcells, 3)
    integer(k8), intent(in) :: pcell_equiv_atom_label(def_numcells)
    
    !Local variables
    integer(k8) :: nstates, nstates_irred, chunk, start, end, num_active_images, &
         istate1, s1, iq1_ibz, iq1, s2, iq2, i, j, num_dof_def, a, dof_counter, iq, &
         tau_sc, tau_uc
    real(dp) :: en1_sq
    complex(dp) :: d0_istate, phase
    complex(dp), allocatable :: phi(:, :, :), phi_internal(:), D0(:, :, :)
   
    !Total number of IBZ and FBZ blocks states
    nstates_irred = ph%nwv_irred*ph%numbands
    nstates = ph%nwv*ph%numbands

    !Total number of degrees of freedom in defective supercell
    num_dof_def = def_numcells*3
    
    !Divide phonon states among images
    call distribute_points(nstates_irred, chunk, start, end, num_active_images)

    allocate(phi(ph%nwv, ph%numbands, num_dof_def), phi_internal(num_dof_def), &
         D0(nstates_irred, num_dof_def, num_dof_def))

    !Precompute the defective supercell eigenfunctions
    do iq = 1, ph%nwv
       dof_counter = 0
       do tau_sc = 1, def_numcells !Atoms in defective supercell
          !Phase factor
          phase = expi( &
               twopi*dot_product(ph%wavevecs(iq, :), def_supercell_atompos(tau_sc, :)) )

          !Get primitive cell equivalent atom of supercell atom
          tau_uc = pcell_equiv_atom_label(tau_sc)

          !Run over Cartesian directions
          do a = 1, 3
             dof_counter = dof_counter + 1
             phi(iq, :, dof_counter) = phase*ph%evecs(iq, :, (tau_uc - 1)*3 + a)
          end do
       end do
    end do

    !Initialize D0
    D0 = 0.0_dp
    
    !Run over first (IBZ) phonon states
    do istate1 = start, end
       !Demux state index into branch (s) and wave vector (iq) indices
       call demux_state(istate1, ph%numbands, s1, iq1_ibz)

       !Muxed index of wave vector from the IBZ index list.
       !This will be used to access IBZ information from the FBZ quantities.
       !Recall that for the phonons, unlike for the electrons, we don't save these IBZ info separately.
       iq1 = ph%indexlist_irred(iq1_ibz)
       
       !Squared energy of phonon 1
       en1_sq = ph%ens(iq1, s1)**2
       
       !Sum over internal (FBZ) phonon wave vectors
       do iq2 = 1, ph%nwv
          !Sum over internal phonon bands
          do s2 = 1, ph%numbands
             phi_internal(:) = phi(iq2, s2, :)

             d0_istate = resolvent(ph, s2, iq2, en1_sq) 

             do j = 1, num_dof_def
                do i = 1, num_dof_def
                   D0(i, j, istate1) = D0(i, j, istate1) + &
                        d0_istate*conjg(phi_internal(i))*phi_internal(j)
                end do
             end do
          end do
       end do
    end do

    !Reduce D0
    call co_sum(D0)
  end subroutine calculate_retarded_phonon_D0

  subroutine calculate_phonon_Tmatrix(D0, V, T, approx)
    !! Calculates the scattering T-matrix for phonons for a given approximation.
    !!
    !! D0 Retarded, bare Green's function
    !! V Scattering potential
    !! T Scattering T-matrix
    !! approx Approximation

    complex(dp), intent(in) :: D0(:, :, :)
    real(dp), intent(in) :: V(:, :)
    character(len=*), intent(in) :: approx
    complex(dp), allocatable, intent(out) :: T(:, :, :)

    !Local variables
    integer(k8) :: num_def_dof, numstates_irred, istate, nstates_irred, &
         chunk, start, end, num_active_images
    complex(dp), allocatable :: inv_one_minus_VD0(:, :)

    !Displacement degrees of freedom in the defective supercell 
    num_def_dof = size(D0(:, 1, 1))

    !Number of irreducible phonon states
    numstates_irred = size(D0(1, 1, :))

    allocate(T(num_def_dof, num_def_dof, numstates_irred))

    !Divide phonon states among images
    call distribute_points(nstates_irred, chunk, start, end, num_active_images)
    
    do istate = start, end
       select case(approx)
       case('lowest order')
          ! Lowest order:
          ! T = V
          !                            
          !    *                     
          !    |                        
          !  V |                         
          !    |
          !                
          T(:, :, istate) = V
       case('1st Born')
          ! 1st Born approximation:
          ! T = V + V.D0.V
          !                            
          !    *             *            
          !    |            / \              
          !  V |     +     /   \              
          !    |          /_____\
          !                 D0
          T(:, :, istate) = V + matmul(matmul(V, D0(:, :, istate)), V)
       case('full Born')
          ! Full Born approximation:
          ! T = V + V.D0.T = [I - VD0]^-1 . T
          !                              _                                      _
          !    *             *          |    *         *            *            |
          !    |            /           |    |        / \          /|\           |
          !  V |     +     /       x    |    |   +   /   \   +    / | \  +  ...  |
          !    |          /_____        |_   |      /_____\      /__|__\        _|
          !                 D0           
          !
          allocate(inv_one_minus_VD0(num_def_dof, num_def_dof))
          inv_one_minus_VD0 = 1.0_dp - matmul(V, D0(:, :, istate))
          call invert(inv_one_minus_VD0)
          T(:, :, istate) = matmul(inv_one_minus_VD0, V)
       case default
          call exit_with_message("T-matrix approximation not recognized.")
       end select
    end do
    
    call co_sum(T)
  end subroutine calculate_phonon_Tmatrix
end module Green_function
