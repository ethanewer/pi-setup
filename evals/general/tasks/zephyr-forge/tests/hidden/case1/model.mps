*SENSE:Minimize
NAME          zf
ROWS
 N  OBJ
 G  _C1
 G  _C2
 G  _C3
COLUMNS
    MARK      'MARKER'                 'INTORG'
    x0        _C1        1.000000000000e+00
    x0        _C2        1.000000000000e+00
    x0        OBJ        3.000000000000e+00
    MARK      'MARKER'                 'INTEND'
    MARK      'MARKER'                 'INTORG'
    x1        _C1        1.000000000000e+00
    x1        _C3        1.000000000000e+00
    x1        OBJ        2.000000000000e+00
    MARK      'MARKER'                 'INTEND'
    MARK      'MARKER'                 'INTORG'
    x2        _C1        1.000000000000e+00
    x2        _C2        2.000000000000e+00
    x2        OBJ        5.000000000000e+00
    MARK      'MARKER'                 'INTEND'
    MARK      'MARKER'                 'INTORG'
    x3        _C1        1.000000000000e+00
    x3        _C3        1.000000000000e+00
    x3        OBJ        6.000000000000e+00
    MARK      'MARKER'                 'INTEND'
    MARK      'MARKER'                 'INTORG'
    z         _C1        2.000000000000e+00
    z         _C3        1.000000000000e+00
    z         OBJ        1.000000000000e+01
    MARK      'MARKER'                 'INTEND'
RHS
    RHS       _C1        5.000000000000e+00
    RHS       _C2        1.000000000000e+00
    RHS       _C3        2.000000000000e+00
BOUNDS
 BV BND       x0      
 BV BND       x1      
 BV BND       x2      
 BV BND       x3      
 UP BND       z          3.000000000000e+00
ENDATA
