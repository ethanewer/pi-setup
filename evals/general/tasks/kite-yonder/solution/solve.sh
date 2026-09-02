#!/bin/bash
# Real oracle for kite-yonder.
# Installs the authored pieces of the "ring" stack into /app (the environment
# already provides the physics/PL fixtures: sim/*, cir/src/*, bind/pad.c,
# tpl/legacy.hpp, gen/demo.json), then RUNS /app/solve.py which builds every
# component and writes /app/answer.json by doing real work.
set -e
S=/solution
mkdir -p /app/gen /app/sim /app/cir /app/tpl /app/bind
install -m 0644 "$S/sampler.c"      /app/gen/sampler.c
install -m 0644 "$S/Makefile.sim"   /app/sim/Makefile
install -m 0644 "$S/CMakeLists.cir" /app/cir/CMakeLists.txt
install -m 0644 "$S/series.hpp"     /app/tpl/series.hpp
install -m 0644 "$S/bad.py"         /app/bind/bad.py
install -m 0644 "$S/solve.py"       /app/solve.py
python3 /app/solve.py