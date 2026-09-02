MODULE geom
  IMPLICIT NONE
  REAL, PARAMETER :: G = 9.80665
CONTAINS
  REAL FUNCTION ballistics_range(v0, ang_deg)
    REAL, INTENT(IN) :: v0
    REAL, INTENT(IN) :: ang_deg
    REAL :: rad
    rad = ang_deg * 3.141592653589793 / 180.0
    ballistics_range = (v0 * v0 * SIN(2.0 * rad)) / G
  END FUNCTION ballistics_range
END MODULE geom