*SENSE:Minimize
NAME          zf
ROWS
 N  OBJ
 L  _C1
 G  _C2
 G  _C3
COLUMNS
    MARK      'MARKER'                 'INTORG'
    w         _C2        1.000000000000e+00
    w         _C3        1.000000000000e+00
    w         OBJ        1.000000000000e+00
    MARK      'MARKER'                 'INTEND'
    MARK      'MARKER'                 'INTORG'
    x0        _C1        1.000000000000e+00
    x0        _C2        1.000000000000e+00
    x0        _C3        2.000000000000e+00
    x0        OBJ        6.000000000000e+00
    MARK      'MARKER'                 'INTEND'
    MARK      'MARKER'                 'INTORG'
    x1        _C1        1.000000000000e+00
    x1        _C2       -1.000000000000e+00
    x1        OBJ        5.000000000000e+00
    MARK      'MARKER'                 'INTEND'
    MARK      'MARKER'                 'INTORG'
    x2        _C1        1.000000000000e+00
    x2        _C2        1.000000000000e+00
    x2        _C3        4.000000000000e+00
    x2        OBJ        4.000000000000e+00
    MARK      'MARKER'                 'INTEND'
    MARK      'MARKER'                 'INTORG'
    x3        _C1        1.000000000000e+00
    x3        _C2       -1.000000000000e+00
    x3        OBJ        3.000000000000e+00
    MARK      'MARKER'                 'INTEND'
RHS
    RHS       _C1        2.000000000000e+00
    RHS       _C2        1.000000000000e+00
    RHS       _C3        3.000000000000e+00
BOUNDS
 UP BND       w          5.000000000000e+00
 BV BND       x0      
 BV BND       x1      
 BV BND       x2      
 BV BND       x3      
ENDATA
