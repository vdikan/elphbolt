module misc
  !! Module containing miscellaneous math and numerics related functions and subroutines.

  use params, only: dp, k4

  implicit none

contains

  subroutine exit_with_message(message)
    !! Exit with error message.

    character(len=*), intent(in) :: message

    if(this_image() == 1) then
       print*, trim(message)
       stop
    end if
  end subroutine exit_with_message

  subroutine print_message(message)
    !! Print message.
    
    character(len=*), intent(in) :: message

    if(this_image() == 1) print*, trim(message)
  end subroutine print_message

  subroutine int_div(num,denom,q,r)
    !! Quotient(q) and remainder(r) of the integer division num/denom.

    integer(k4), intent(in) :: num, denom
    integer(k4), intent(out) :: q, r

    q = num/denom
    r = mod(num, denom)
  end subroutine int_div
  
  function cross_product(A,B)
    !! Cross product of A and B.

    real(dp), intent(in) :: A(3), B(3)
    real(dp) :: cross_product(3)

    cross_product(1) = A(2)*B(3) - A(3)*B(2)
    cross_product(2) = A(3)*B(1) - A(1)*B(3)
    cross_product(3) = A(1)*B(2) - A(2)*B(1)
  end function cross_product

  function expix(x)
    !! Calculate exp(i*x) = cos(x) + isin(x)
    implicit none

    real(dp), intent(in) :: x
    complex(dp) :: expix

    expix = cmplx(cos(x), sin(x))
  end function expix

  subroutine sort_int(list)
    !! Swap sort list of integers

    integer(k4), intent(inout) :: list(:)
    integer(k4) :: i, j, n
    integer(k4) :: aux, tmp
    
    n = size(list)

    do i = 1, n
       aux = list(i)
       do j = i + 1, n
          if (aux > list(j)) then
             tmp = list(j)
             list(j) = aux
             list(i) = tmp
             aux = tmp
          end if
       end do
    end do
  end subroutine sort_int
  
  function mux_vector(v,mesh,base)
    !! Multiplex index of a single wave vector.
    !! v is the demultiplexed triplet of a wave vector.
    !! i is the multiplexed index of a wave vector (always 1-based).
    !! mesh is the number of wave vectors along the three reciprocal lattice vectors.
    !! base states whether v has 0- or 1-based indexing.

    integer(k4), intent(in) :: v(3), mesh(3), base
    integer(k4) :: mux_vector 

    if(base < 0 .or. base > 1) then
       call exit_with_message("Base has to be either 0 or 1 in index.f90:mux_vector")
    end if

    if(base == 0) then
       mux_vector = (v(3)*mesh(2) + v(2))*mesh(1) + v(1) + 1
    else
       mux_vector = ((v(3) - 1)*mesh(2) + (v(2) - 1))*mesh(1) + v(1)
    end if
  end function mux_vector

  subroutine demux_vector(i,v,mesh,base)
    !! Demultiplex index of a single wave vector.
    !! i is the multiplexed index of a wave vector (always 1-based).
    !! v is the demultiplexed triplet of a wave vector.
    !! mesh is the number of wave vectors along the three.
    !! reciprocal lattice vectors.
    !! base chooses whether v has 0- or 1-based indexing.
    
    integer(k4), intent(in) :: i, mesh(3), base
    integer(k4), intent(out) :: v(3)
    integer(k4) :: aux

    if(base < 0 .or. base > 1) then
       call exit_with_message("Base has to be either 0 or 1 in index.f90:demux_vector")
    end if

    call int_div(i - 1, mesh(1), aux, v(1))
    call int_div(aux, mesh(2), v(3), v(2))
    if(base == 1) then
       v(1) = v(1) + 1
       v(2) = v(2) + 1
       v(3) = v(3) + 1 
    end if
  end subroutine demux_vector
  
  subroutine demux_mesh(index_mesh,nmesh,mesh,base,indexlist)
    !! Demultiplex all wave vector indices 
    !! (optionally, from a list of indices).
    !! Internally uses demux_vector.

    integer(k4), intent(in) :: nmesh, mesh(3), base
    integer(k4), optional, intent(in) :: indexlist(nmesh)
    integer(k4), intent(out) :: index_mesh(3, nmesh)
    integer(k4) :: i

    do i = 1, nmesh !over total number of wave vectors
       if(present(indexlist)) then
          call demux_vector(indexlist(i), index_mesh(:, i), mesh, base)
       else
          call demux_vector(i, index_mesh(:, i), mesh, base)
       end if
    end do
  end subroutine demux_mesh

  function mux_state(nbands, iband, ik)
    !! Multiplex a (band index, wave vector index) pair into a state index 
    !!
    !! nbands is the number of bands
    !! iband is the band index
    !! ik is the wave vector index
    
    integer(k4), intent(in) :: nbands, ik, iband 
    integer(k4) :: mux_state

    mux_state = (ik - 1)*nbands + iband
  end function mux_state

  subroutine demux_state(m, nbands, iband, ik)
    !!Demultiplex a state index into (band index, wave vector index) pair
    !!
    !! m is the multiplexed state index
    !! nbands is the number of bands
    !! iband is the band index
    !! ik is the wave vector index
    
    integer(k4), intent(in) :: m, nbands
    integer(k4), intent(out) :: ik, iband 

    iband = modulo(m - 1, nbands) + 1
    ik = int((m - 1)/nbands) + 1
  end subroutine demux_state
end module misc
