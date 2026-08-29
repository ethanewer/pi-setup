# Dune Terrace — software rasterization output (no GPU, no display)

You are given a scene description and asked to build three small, real tools
that produce raster image output on a machine with **no GPU and no display
server**. You write your own offscreen pixel pipelines and emit binary image
files yourself — you never "load" or embed an existing picture.

## Working environment

- You work in `/app`. A scene description is at `/app/scene.json`.
- A C compiler (`cc` / gcc 13) and `python3` (3.12, with `zlib`) are available.
- **Do not modify** any input file, especially `/app/scene.json`.
- Everything must be deterministic and computed from the scene — you must not
  embed or copy a pre-rendered image into any deliverable.

## Deliverables (all created in `/app`)

1. `/app/make_icon.py` — deterministic PNG icon generator.
2. `/app/ptrace.c` — compact C ray tracer (renders the scene offscreen).
3. `/app/scene_color.pfm` — float RGB color raster (produced by `ptrace.c`).
4. `/app/scene_depth.pgm` — depth/distance raster (produced by `ptrace.c`).
5. `/app/out.png` — the 64x64 PNG icon (rendered by `make_icon.py`).

Also produce `/app/target.ppm` — a `P6` color reconstruction made by running
`ptrace.c` (the "target image" the tracer reconstructs from the scene data,
never from a reference file).

## The scene (`/app/scene.json`)

```json
{
  "width": 160, "height": 100,
  "camera": {"eye":[0.0,0.3,3.6], "center":[0.0,0.0,0.0], "up":[0.0,1.0,0.0], "fov":50.0},
  "background_bottom":[245,195,130],
  "background_top":[30,90,210],
  "ambient":0.3, "max_depth":7.0,
  "light": {"pos":[-2.5,4.0,1.0], "color": [255,225,205]},
  "objects": [
    {"center":[0.0,0.0,-1.8],   "radius":0.70, "color":[200,40,45],  "reflect":0.05,"shin":40},
    {"center":[-1.3,-0.5,-1.9], "radius":0.80, "color":[60,170,120], "reflect":0.05,"shin":16},
    {"center":[1.3,-0.5,-1.5],  "radius":0.70, "color":[70,100,220], "reflect":0.10,"shin":60},
    {"center":[0.05,0.6,-2.5],  "radius":0.95, "color":[230,190,110],"reflect":0.15,"shin":80}
  ]
}
```

Your C renderer reads only **`width`** and **`height`** from `scene.json` (the
geometry is fixed — use the constants above). It must build output at exactly
that `width x height`. If `width` or `height` is missing or `<= 0`, fall back
to **160 x 100**. It must handle the tiny canvas `1 x 1` and a very-tall canvas
such as `80 x 240` without crashing — it just renders at those sizes.

## Part 1 — `/app/ptrace.c` (compact C path tracer)

A single C file compiled by the verifier with:

```
cc -O2 -o /tmp/ptrace /app/ptrace.c -lm
```

Runtime usage (exact argument order):

```
ptrace <scene.json> <target.ppm> <scene_color.pfm> <scene_depth.pgm>
```

It renders the sphere scene and writes the three files. Implementation
specification (follow it exactly so your result is deterministic):

**Camera.** eye `e=(0,0.3,3.6)`, look-at `c=(0,0,0)`, world up `u=(0,1,0)`,
vertical FOV **50°**. Build basis: `fwd=normalize(c-e)`,
`rgt=normalize(cross(fwd,u))`, `up=cross(rgt,fwd)`. For pixel `(x,y)`:

```
px = 2.0*(x+0.5)/W - 1.0
py = 1.0 - 2.0*(y+0.5)/H
t  = tan(50.0 * pi / 360.0)          // pi/180 * 50 / 2
aspect = W/H
dir = normalize( fwd + rgt*(px*aspect*t) + up*(py*t) )
```

**Sphere hit** for center `s`, radius `r`, ray origin `eye`, direction `dir`:
`oc = eye - s;  b = dot(oc,dir);  c2 = dot(oc,oc) - r*r;  disc = b*b - c2`.
If `disc < 0` no hit. Else `t0 = -b - sqrt(disc)`, use it if `t0 >= 1e-5`,
otherwise use `t1 = -b + sqrt(disc)`; if still `< 1e-5` no hit. Keep the
smallest valid `t` over the four spheres; if none, the ray misses.

**Color.** On a hit at `P`, normal `n = normalize(P - center)`; flip signs so it
points against the ray inside the object. Light origin `L=(-2.5,4.0,1.0)`, light
color `Lc = (255,225,205)/255`, ambient `amb=0.30`, object base `bc = color/255`.

- `toL = normalize(L - P)`.
- **Shadow**: from `Ps = P + n*1e-4` cast toward `toL`. If any other sphere
  intersects with `t` in `(1e-5, |L-P| - 1e-4)`, the point is shadowed. Let
  `sh = 0.0` if shadowed else `1.0`.
- `diff = max(dot(n, toL), 0)`.
- `V = -dir`. `R = 2*dot(n,toL)*n - toL` (reflect the light vector).
  `spec = pow(max(dot(R,V),0), shin)`.
- Surface color, per channel:
  `channel = bc[i]*(amb + 0.55*diff*sh) + Lc[i]*0.8*spec*sh`.
- **Reflection bounce**: if `reflect > 0`, reflect the ray about the normal
  `rd2 = dir - 2*dot(n,dir)*n`, recurse once (depth 1) from `P + n*1e-4`, and
  add `reflect * reflectedColor` to the result. Clamp each channel to `[0,1]`.

**Miss / sky:** `g = clamp((dot(dir, up)+1)*0.5, 0, 1)` where `up` is the
camera basis's `up`; channel `i` = `BGB[i]*(1-g) + BGT[i]*g` with
`BGB=background_bottom/255=(245,195,130)/255` and
`BGT=background_top/255=(30,90,210)/255`.

**Depth value:** for the nearest hit `t_min`, `d = clamp(t_min/7.0,0,1)` and
write `round(d*255)`; a missing ray writes `255`.

### Exact output file formats (bitmaps and colors are deterministic, no RNG)

- `target.ppm` — **P6**:
  header `P6\n<W> <H>\n255\n` then `W*H*3` bytes in **row-major top-first**
  order, RGB each `round(c*255)`, `c` in `0..1`.
- `scene_color.pfm` — **PFM**:
  header `PF\n<W> <H>\n-1.0\n` then `W*H` samples of **float32** RGB triples
  (`0..1`) written **bottom-up**: row `H-1` first, ending with row `0`.
- `scene_depth.pgm` — **PGM (P5)**:
  header `P5\n<W> <H>\n255\n` then `W*H` bytes in **row-major top-first**
  order.

These three must reproduce byte-for-byte on every run.

### Source-size budget (hard constraint)

`/app/ptrace.c` must be a genuinely small program. The verifier checks its
`gzip -c ptrace.c | wc -c <= 5000`. Embedding a pre-rendered image (large byte
arrays) blows past this budget and fails. Keep it compact.

## Part 2 — `/app/make_icon.py` (PNG icon)

Runnable as `python3 /app/make_icon.py <out.png>`. It draws a **deterministic
64x64 RGB PNG** "dune sunset" icon — a vertical gradient sky, a sun disc, two
rolling dune bands, and the word **SUNSET** rendered with a small 5x7 bitmap
font — and writes a valid PNG to the given path. Output must be byte-for-byte
identical each run (no timestamps, no randomness, fixed zlib usage), be a valid
PNG, and be exactly `64 x 64`. It must be able to create `/app/out.png` from
`python3 /app/make_icon.py /app/out.png`.

## How you are scored (so you can reason about it)

1. The 5 deliverables (+`/app/target.ppm`) must exist.
2. `ptrace.c` is recompiled and re-run on `/app/scene.json`; the produced
   `target.ppm`, `scene_color.pfm` and `scene_depth.pgm` must match the
   reference within **SSIM >= 0.94** (depth additionally: `>= 95%` of pixels
   within `5` grey levels).
3. `ptrace.c` gzip size must be `<= 5000`.
4. `make_icon.py` is re-run by the verifier: the produced PNG must (a) be a valid
   `64 x 64` 8-bit RGB PNG that decodes cleanly, (b) actually depict the described
   scene — a cool vertical-gradient sky, a bright sun disc, warm rolling dune
   bands, and the glyph-like `SUNSET` word in a lower band — and (c) be
   byte-for-byte identical across two consecutive runs (the exact colors,
   positions, font raster and zlib encoding are left to you, but whatever you
   choose must be deterministic).
5. `ptrace.c` run on hidden scenes (`1x1`, `80x240`, one lacking
   `width`/`height`) must produce PPM/PFM/PGM whose headers match the scene
   dimensions (falling back to `160x100` when omitted).

If a rendering decision is not forced above, choose any concrete value — but a
single correct, deterministic implementation is what the reference threshold
rewards, so match the constants and order of operations above exactly.

## Notes

- Plain `zlib` + `struct` is enough for the PNG; plain `fopen`/`fwrite` covers
  the binary formats. Third-party image libraries are not required (and not all
  are preinstalled).
- Execute things by running them; end of the day `/app/scene.*.pfm/.pgm`,
  `/app/out.png` and `/app/target.ppm` must literally exist where stated.
- Work only inside `/app`.

Good luck — your scoring is strict about formats and sizes.