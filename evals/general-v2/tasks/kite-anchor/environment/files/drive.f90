PROGRAM drive
  USE geom
  IMPLICIT NONE
  REAL :: v0, ang
  READ(*,*) v0, ang
  WRITE(*,'(F12.3)') ballistics_range(v0, ang)
END PROGRAM drive