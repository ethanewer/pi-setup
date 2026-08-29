! Library module for the small numeric experiment (fixture, do not edit).
module series_mod
  implicit none
contains
  function sum_squares(n) result(s)
    integer, intent(in) :: n
    integer :: s, i
    s = 0
    do i = 1, n
      s = s + i*i
    end do
  end function sum_squares
end module series_mod
