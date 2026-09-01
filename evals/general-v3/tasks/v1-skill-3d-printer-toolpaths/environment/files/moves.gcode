G90 ; absolute positioning
G21 ; all dimensions in millimetres
; -- travel to the print-start corner (NOT counted)
G0 X5 Y5 Z0
; -- extruded contour moves (each counted)
G1 X30 Y5 Z0
G1 X30 Y20 Z0
G1 X5 Y20 Z0
G1 X5 Y30 Z0