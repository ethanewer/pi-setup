! Main program for the small numeric experiment (fixture, do not edit).
! Reads one integer n on stdin and prints the sum of squares 1..n.
program main_series
  use series_mod
  implicit none
  integer :: n, r
  read(*,*) n
  r = sum_squares(n)
  print '(I0)', r
end program main_series
