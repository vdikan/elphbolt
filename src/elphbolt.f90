program elphBolt
  !! Author: Nakib H. Protik
  !! Summary: Main driver program.
  !!
  !! elphBolt is a program for solving the coupled electron-phonon Boltzmann
  !! transport equations (e-ph BTEs) as formulated in Phys. Rev. B 101, 075202 (2020)
  !! and Phys. Rev. B 102, 245202 (2020) with both the electron-phonon and phonon-phonon
  !! interactions computed ab initio.

  use params, only: k4, dp
  use numerics_module, only: numerics
  use crystal_module, only: crystal
  use symmetry_module, only: symmetry
  use electron_module, only: electron
  use phonon_module, only: phonon
  use wannier_module, only: epw_wannier
  use bte_module, only: bte
  use bz_sums, only: calculate_dos
  use interactions, only:  calculate_g_mixed, calculate_g2_bloch, calculate_3ph_interaction
  
  implicit none
  
  type(numerics) :: num
  type(crystal) :: crys
  type(symmetry) :: sym
  type(epw_wannier) :: wann
  type(electron) :: el
  type(phonon) :: ph
  type(bte) :: bt

  if(this_image() == 1) then
     print*, 'Number of images = ', num_images()
  end if

  !Set up crystal
  call crys%initialize
  
  !Set up numerics data
  call num%initialize
  
  !Calculate crystal and BZ symmetries
  call sym%calculate_symmetries(crys, num%qmesh)

  !Read EPW Wannier data
  call wann%read

!!$  !Test electron bands, phonon dispersions, and g along path.
!!$  if(this_image() == 1) then
!!$     call wann%test_wannier(crys, num)
!!$  end if
  
  !Calculate electrons
  call el%initialize(wann, crys, sym, num)

  !Calculate electron density of states
  call calculate_dos(el, num%tetrahedra)
  
  !Calculate phonons
  call ph%initialize(wann, crys, sym, num)

  !Calculate phonon density of states
  call calculate_dos(ph, num%tetrahedra)
  
!!$  !Calculate mixed Bloch-Wannier space e-ph vertex
!!$  call calculate_g_mixed(wann, el, num)
!!$
!!$  !Calculate Bloch space e-ph vertex
!!$  !TODO call calculate_g2_bloch(wann, crys, el, ph, num)
!!$  !TODO need to fix this for unequal k and q meshes

  if(.not. num%read_V) then
     !Calculate ph-ph vertex
     call calculate_3ph_interaction(ph, crys, num, 'V')
  end if
  
  !Calculate transition probabilities
  call calculate_3ph_interaction(ph, crys, num, 'W')
  
  !RTA solution
  call bt%solve_rta_ph(num, crys, sym, ph)
end program elphBolt
