*SENSE:Minimize
NAME          zf
ROWS
 N  OBJ
 G  _C1
 L  _C2
 L  _C3
COLUMNS
    MARK      'MARKER'                 'INTORG'
    x0        _C1        1.000000000000e+00
    x0        _C2        1.000000000000e+00
    x0        OBJ        2.000000000000e+00
    MARK      'MARKER'                 'INTEND'
    MARK      'MARKER'                 'INTORG'
    x1        _C1        2.000000000000e+00
    x1        _C3        1.000000000000e+00
    x1        OBJ        3.000000000000e+00
    MARK      'MARKER'                 'INTEND'
    MARK      'MARKER'                 'INTORG'
    x2        _C1       -1.000000000000e+00
    x2        _C2        1.000000000000e+00
    x2        OBJ        5.000000000000e+00
    MARK      'MARKER'                 'INTEND'
    MARK      'MARKER'                 'INTORG'
    y         _C1        1.000000000000e+00
    y         _C3        2.000000000000e+00
    y         OBJ        4.000000000000e+00
    MARK      'MARKER'                 'INTEND'
RHS
    RHS       _C1        4.000000000000e+00
    RHS       _C2        1.000000000000e+00
    RHS       _C3        9.000000000000e+00
BOUNDS
 BV BND       x0      
 BV BND       x1      
 BV BND       x2      
 UP BND       y          6.000000000000e+00
ENDATA
