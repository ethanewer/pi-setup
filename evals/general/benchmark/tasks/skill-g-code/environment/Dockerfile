FROM bench-base:python-3.12

WORKDIR /app

RUN printf '%s\n' \
    '; absolute mode program' \
    'G90' \
    'G0 X0 Y0' \
    'G1 X10 Y5' \
    'G1 X5 Y-4' \
    'G1 X2 Y8' > /app/move.gcode