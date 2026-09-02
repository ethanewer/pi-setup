module snowmod
  implicit none
contains
  pure integer function count_above(vals, n, thresh)
    integer, intent(in) :: n
    real, intent(in) :: vals(n)
    real, intent(in) :: thresh
    integer :: i
    count_above = 0
    do i = 1, n
      if (vals(i) > thresh) count_above = count_above + 1
    end do
  end function count_above

  pure real function mean_val(vals, n)
    integer, intent(in) :: n
    real, intent(in) :: vals(n)
    integer :: i
    real :: s
    s = 0.0
    do i = 1, n
      s = s + vals(i)
    end do
    mean_val = s / real(n)
  end function mean_val

  pure real function peak_val(vals, n)
    integer, intent(in) :: n
    real, intent(in) :: vals(n)
    integer :: i
    peak_val = vals(1)
    do i = 2, n
      if (vals(i) > peak_val) peak_val = vals(i)
    end do
  end function peak_val
end module snowmod
