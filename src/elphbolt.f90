! Copyright (C) 2020- Nakib Haider Protik <nakib.haider.protik@gmail.com>
! This file is part of elphbolt <https://github.com/nakib/elphbolt>.
!
! elphbolt is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation, either version 3 of the License, or
! (at your option) any later version.
!
! elphbolt is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with elphbolt. If not, see <http://www.gnu.org/licenses/>.

program elphbolt
  !! Author: Nakib Haider Protik
  !! Summary: Main driver program.
  !!
  !! elphbolt is a program for solving the coupled electron-phonon Boltzmann
  !! transport equations (e-ph BTEs) as formulated in Phys. Rev. B 101, 075202 (2020)
  !! and Phys. Rev. B 102, 245202 (2020) with both the electron-phonon and phonon-phonon
  !! interactions computed ab initio.

  use misc, only: welcome, print_message, subtitle
  use params, only: k8, dp
  use numerics_module, only: numerics
  use crystal_module, only: crystal
  use symmetry_module, only: symmetry
  use electron_module, only: electron
  use phonon_module, only: phonon
  use wannier_module, only: epw_wannier
  use bte_module, only: bte
  use bz_sums, only: calculate_dos, calculate_chempot, calculate_qTF
  use interactions, only: calculate_gReq, calculate_gkRp, calculate_3ph_interaction, &
       calculate_eph_interaction_ibzq, calculate_eph_interaction_ibzk
  
  implicit none
  
  type(numerics) :: num
  type(crystal) :: crys
  type(symmetry) :: sym
  type(epw_wannier) :: wann
  type(electron) :: el
  type(phonon) :: ph
  type(bte) :: bt

  !Print banner and other info.
  call welcome
  
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

  !Calculate chemical potential
  call calculate_chempot(el, crys%T, crys%volume)

  !Calculate Thomas-Fermi screening
  call calculate_qTF(crys, el)
  
  !Calculate phonons
  call ph%initialize(wann, crys, sym, num)

  !Calculate phonon density of states
  call calculate_dos(ph, num%tetrahedra, crys%gfactors, &
       crys%atomtypes, bt%ph_rta_rates_iso_ibz, num%phiso)

  call subtitle("Calculating interactions...")
  
  if(num%phe) then
     if(.not. num%read_gq2) then
        !Calculate mixed Bloch-Wannier space e-ph vertex g(Re,q)
        call calculate_gReq(wann, ph, num)

        !Calculate Bloch space e-ph vertex g(k,q) for IBZ q
        call calculate_eph_interaction_ibzq(wann, crys, el, ph, num, 'g')
     end if
     
     !Calculate ph-e transition probabilities
     call calculate_eph_interaction_ibzq(wann, crys, el, ph, num, 'Y')
  end if

  if(.not. num%read_gk2) then
     !Calculate mixed Bloch-Wannier space e-ph vertex g(k,Rp)
     call calculate_gkRp(wann, el, num)

     !Calculate Bloch space e-ph vertex g(k,q) for IBZ k
     call calculate_eph_interaction_ibzk(wann, crys, el, ph, num, 'g')
  end if

  !Calculate e-ph transition probabilities
  call calculate_eph_interaction_ibzk(wann, crys, el, ph, num, 'X')

  !Calculate e-ch. imp. transition probabilities
  !TODO call calculate_echimp_interaction_ibzk()

  if(num%phbte) then
     if(.not. num%read_V) then
        !Calculate ph-ph vertex
        call calculate_3ph_interaction(ph, crys, num, 'V')
     end if

     !Calculate ph-ph transition probabilities
     call calculate_3ph_interaction(ph, crys, num, 'W')
  end if

  !Deallocate Wannier quantities
  call wann%deallocate_wannier
  
  !Solve BTEs
  call bt%solve_bte(num, crys, sym, ph, el)

  call print_message('______________________Thanks for using elphbolt. Bye!______________________')
end program elphbolt
