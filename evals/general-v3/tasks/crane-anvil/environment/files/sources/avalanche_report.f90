program avalanche_report
  use snowmod
  implicit none
  character(len=256) :: path
  character(len=64) :: targ
  integer :: n, i, ios, warm
  real :: thresh
  real, allocatable :: vals(:)

  call get_command_argument(1, path)
  call get_command_argument(2, targ)
  read (targ, *) thresh

  open (unit=10, file=trim(path), status='old', action='read', iostat=ios)
  if (ios /= 0) then
    write (*, '(A)') "error: cannot open data file"
    stop 1
  end if
  read (10, *) n
  allocate (vals(n))
  read (10, *) (vals(i), i=1, n)
  close (10)

  warm = count_above(vals, n, thresh)
  write (*, '(A,I0)') "n=", n
  write (*, '(A,I0)') "warm=", warm
  write (*, '(A,F8.2)') "mean=", mean_val(vals, n)
  write (*, '(A,F8.2)') "peak=", peak_val(vals, n)
end program avalanche_report
