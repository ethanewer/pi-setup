#!/bin/bash
# Oracle for slate-anchor: configure the legacy plotsmith tree without the
# X11 frontend, build the headless engine, and run the visible job.
# Never reads /tests.
set -eu

cd /app/plotsmith

# ---- 1. Configure the non-graphical engine (excludes the X11 path).
./configure --without-x

# ---- 2. Build.
make
test -x /app/plotsmith/plotsmith

# ---- 3. Headless linkage sanity: no X11 in the dynamic section.
if readelf -d /app/plotsmith/plotsmith | grep -qi 'x11'; then
    echo "oracle: binary unexpectedly references X11" >&2
    exit 1
fi

# ---- 4. Run the visible job.
/app/plotsmith/plotsmith /app/jobs/visible-job.txt /app/out-map.pbm

echo "solve.sh done"
ls -l /app/plotsmith/plotsmith /app/plotsmith/config.mk /app/out-map.pbm
head -2 /app/out-map.pbm
