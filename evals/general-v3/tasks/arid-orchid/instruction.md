# Arcadia Offscreen Render & Path-Trace Lab

You are standing up a small, self-contained **software rendering stack** inside
`/app` on a headless server: no display server, no GPU, no X, no systemd. Every
render lives in a user-writable area we can call `/app` (treat it as your only
writable directory), and everything you build must run as plain shell commands.

The machine has `gcc`, `python3` (with `numpy` and `Pillow`), and the Mesa
`libOSMesa` software-GL development library installed. Use them freely.

## 1. Working directory and what to produce

All outputs go under `/app`. You will produce **exactly** these files:

| path | contents |
|------|----------|
| `/app/make_icon.py` | executable Python script that renders a PNG scene icon |
| `/app/out.png`     | the PNG icon produced by `make_icon.py` (640x420) |
| `/app/ptrace.c`    | a compact C path-tracer you author (see §2) |
| `/app/ptrace_img.pfm` | color PFM produced by the C path-tracer |
| `/app/render_scene.py` | executable offscreen color+depth rasterizer (see §3) |
| `/app/scene_color.pfm` | color PFM rendered via `render_scene.py` |
| `/app/scene_depth.pgm` | grayscale depth PGM rendered via `render_scene.py` |
| `/app/renderer_env.txt` | a single line: the absolute interpreter path you rendered with |

Anything else (e.g. the compiled binaries, helper scripts, intermediate files)
is fine but optional.

## 2. The scene description file (shared input format)

A **scene** is a plain-text file. Its exact grammar (the same one all your tools
use) is:

```
<W> <H>                # resolution, integers; clamped to [1,1024]
bg <r> <g> <b>         # constant background color, each in [0,1]
amb <a>                # ambient factor in [0,1]
l <x> <y> <z>          # directional light direction (a vector, not required to be unit)
s <cx> <cy> <cz> <radius> <r> <g> <b>   # one diffuse sphere; may appear many times
```

- Lines beginning with `#` are comments and are ignored. Blank lines are
  ignored. Unknown tokens are ignored — never crash on malformed or stray input.
  If a line is two integers and nothing else, treat it as the resolution.
- Whitespace is spaces/tabs. Values parse as decimal numbers; missing or
  non-numeric fields default to `0.0` (never crash).
- The first valid resolution line sets `W,H` and is clamped to `[1,1024]`.
- If no `l` is given, use the default direction `(0.6, 0.8, 0.4)`; if no `amb`
  is given, use `0.35`.

`/app/scene.cfg` is already provided as the default scene — render that scene
for all the deliverables. Hidden evaluator scenes use the same format with
different geometry (including edge/malformed inputs: degenerate/huge radii,
bad tokens, out-of-range sizes) — your tools **must stay robust** on those.

## 3. The C path tracer `/app/ptrace.c`

Author a compact C program (a genuine ray tracer, keep the source small — a
few hundred lines) with command-line contract:

```
./ptrace <scene.cfg> <out.pfm>
```

It reads the scene, and for every pixel casts a single primary ray through a
unit focal plane from an eye at the origin looking down **+Z**, and writes the
result to `out.pfm` in the documented color-PFM format. It must **actually
trace the geometry** given in the scene and shade it — it must never load,
copy, or embed a pre-rendered reference image. If the scene changes, the render
must change accordingly.

**Coordinate / shading model (reproduce this exactly):**

- Pixel `(x,y)`, `0<=x<W`, `0<=y<H` -> a center sample with direction
  `D = normalize( (fx, fy, 1) )` where
  `fx = ((x+0.5) - W/2) * (2/W)` and `fy = (H/2 - (y+0.5)) * (2/W)`.
- Find the nearest positive ray intersection with any sphere (ray-sphere
  root `t` with `t >= 1e-4`).
- If nothing is hit, the pixel is the **background** color and depth is 0.
- Otherwise, with normalized normal `n` and unit light direction `ll =
  normalize(l)`, the brightness is `f = amb + (1-amb)*max(0, n . ll)` and
  `color = baseColor * f` (per channel) clamped to `[0,1]`.
The color buffer is written as a PFM (**see §4**). You may add a small,
*deterministic* ambient/monte-carlo term of your own, but the output must stay
within tolerance of the reference for the documented formula.

The verifier will re-`gcc` your `ptrace.c` and re-run it on hidden scenes.

## 4. Image formats

- **PFM** (color): a PFM format. The exact layout you must emit:
  - line `PF` then newline
  - line `W H` then newline
  - line `-1.0` then newline   (scale < 0 means little-endian)
  - then `W*H*3` IEEE floats in **RGB** channel order (each in `[0,1]`), row
    by row from top to bottom, little-endian byte order.
- **PGM (depth)**: the classic **P2** (ASCII) graymap: line `P2`, line
  `W H`, line `255`, then `W*H` integer values (row-major, `0..255`) separated by
  whitespace. The per-pixel depth value is
  `depth = round( 255 * clamp( 1/(1+t), 0, 1 ) )` where `t` is the hit
  distance; background pixels (no hit) are `0`.

## 5. Color+Depth offscreen renderer `/app/render_scene.py`

`render_scene.py` writes the color and depth buffers through a pure headless
(offscreen, no window) path:

```
python3 render_scene.py <scene.cfg> <out_color.pfm> <out_depth.pgm>
```

It must render the *same* scene/shading model as §3 (single primary ray per
pixel, same focal `fx/fy` geometry, same `amb`+directional lambert shading, same
depth mapping in §4 above, same first-`PF` color PFM header). Use numpy/Pillow to
read and verify nothing wrong — a plain Python loop with `struct` is enough.

## 6. The icon `/app/make_icon.py` and `/app/out.png`

`make_icon.py` must draw a small scene (e.g. a lambert-shaded sphere on a sky
gradient) and write a **640x420 PNG** named `/app/out.png` containing a readable
text phrase of your choice (e.g. a project name). No display is involved.

## 7. OSMesa headless GL proof

The server runs software GL through libOSMesa (already installed). Write a small
C file `/app/osmesa_check.c`, compile it to `/app/osmesa_check` with
`gcc /app/osmesa_check.c -losmesa -lm -o /app/osmesa_check`, and have it:
1. create an `OSMesaContext` (RGBA), make it current on a software buffer;
2. clear it (blue-ish background) and draw at least one colored primitive (e.g.
   a triangle);
3. `glReadPixels` back into the buffer and write a **96x54 P6 PPM** to the path
   given as its first argument.
This is what proves the OSMesa/offscreen GL stack actually works headless.

## 8. Pointer file `/app/renderer_env.txt`

After your renderers succeed, write a **single line** containing the **absolute
path of the Python interpreter you used to produce `/app/scene_color.pfm` and
`/app/scene_depth.pgm`** (e.g. `/usr/local/bin/python3`). It must be an
executable that runs (`-x`). The verifier will read this file, confirm the path
is executable, run it, and use it to re-run your scene renderer. There must be
exactly one line and no extra whitespace.

## 9. Important constraints

- Everything must run with plain shell commands; no systemd, no X, no GPU.
- Do not modify `/tests` or `/solution` — those are mounted read-only.
- The renderers must be **real**: the verifier will re-run them on fresh scenes
  and re-check the outputs; a baked/static image will fail.
- Keep scripts readable and directly runnable. Wrong formats (wrong PFM header,
  integer PGM depth, wrong axes, wrong shading) will be detected on the hidden
  scenes.

Good luck — the raster of the day is a monkey mushroom.