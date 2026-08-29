#!/bin/bash
# Arcadia ARK solution: builds and runs every deliverable under /app.
# It performs the real rendering work (compile + execute the ray tracer, the
# offscreen rasterizer, the icon maker and the OSMesa smoke render) and then
# records the interpreter path that rendered successfully.
set -e
cd /app

SRC=$(dirname "$0")

# 1) C path tracer deliverable + binary
cp -f "$SRC/ptrace.c" /app/ptrace.c
cc -O2 -o /app/ptrace /app/ptrace.c -lm

# 2) offscreen color/depth rasterizer deliverable (python)
cp -f "$SRC/render_scene.py" /app/render_scene.py

# 3) icon generator deliverable
cp -f "$SRC/make_icon.py" /app/make_icon.py

# 4) OSMesa headless GL smoke tool
cp -f "$SRC/osmesa_check.c" /app/osmesa_check.c
gcc -O2 -o /app/osmesa_check /app/osmesa_check.c -lOSMesa -lm

# 5) render everything (the actual work)
/app/ptrace /app/scene.cfg    /app/ptrace_img.pfm
python3 /app/render_scene.py  /app/scene.cfg /app/scene_color.pfm /app/scene_depth.pgm
python3 /app/make_icon.py                              # -> /app/out.png
/app/osmesa_check /app/osmesa_render.ppm               # -> proof of OSMesa

# 6) interpreter pointer file (the python that rendered the color/depth scenes)
PY=$(command -v python3)
echo "$PY" > /app/renderer_env.txt

chmod +x /app/ptrace /app/osmesa_check /app/render_scene.py /app/make_icon.py
echo "solve.sh OK"
ls -la /app | sed -n '1,40p'