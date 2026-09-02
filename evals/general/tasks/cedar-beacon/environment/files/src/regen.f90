      program regen
!     Cedar Beacon kernel reset generator.
!     Writes the canonical sum-pattern line series to the file named by
!     argument 1.  S_k is the finite sum of squares 1^2..k^2.
      implicit none
      integer :: k
      character(len=256) :: fname

      if (command_argument_count() /= 1) then
         write(*, *) 'usage: regen <outfile>'
         stop 1
      end if
      call get_command_argument(1, fname)

      open(unit=10, file=trim(fname), status='replace')
      do k = 1, 12
         write(10, '(a,i3,a,i12)') 'S_', k, ' ', (k*(k+1)*(2*k+1))/6
      end do
      close(unit=10)
      end program regen
