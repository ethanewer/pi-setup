#!/bin/bash
set -euo pipefail

cat > /app/scene.pov <<'P'
#include "colors.inc"

camera {
    location <0,0,-10>
    look_at <0,0,0>
}

light_source {
    <0, 10, -20>
    color rgb <1,1,1>
}

sphere {
    <0,0,0>, 1
    pigment {
        color rgb <1,0,0>
    }
}
P