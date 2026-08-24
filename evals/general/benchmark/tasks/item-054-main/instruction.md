# Item-054 (main) — Reproduce a reference ray tracer

You are an expert C programmer working inside a container with `/app/pov/` containing:

- `README.md` — the SCENE FILE format and the CLI contract, but **not** the full projection
  parameters (it says the mapping is "linear and symmetric" — specifics are left for you to determine).
- `render_ref` — an authoritative precompiled renderer (read the scene file, produce a PPM).
- `scene0.pov`, `scene0.ppm` — one sample input/output pair produced by `render_ref`.
- `check.py` — a PPM comparator: prints the fraction of differing bytes.

The scene format:
```
size <W> <H>            (optional; defaults 64 48)
background <r> <g> <b>       (floats 0..1; default 0.05 0.05 0.10)
sphere <x> <y> <radius> <r> <g> <b>   (`x`,`y` are world coords on [-3, 3])
```

The renderer maps world positions to pixels by an unknown linear symmetric mapping with a
shared scale for x and y. **Later spheres are drawn on top of earlier ones.**
Fill rule: pixel is part of a sphere when `(du)^2 + (dv)^2 <= r_screen^2` where
`u = 2*px/(W-1) - 1`, etc., and the screen radius depends on the focal length.
Your `tracer` must match the reference **byte-for-byte** within a small recovered tolerance.

Your job: write `/app/pov/tracer.c`, compile it to `/app/pov/tracer` (gcc is installed), so that on
**every** valid scene it reproduces the reference exactly — including hidden `edge` cases in verifier tests.
You may (a) run `render_ref` on crafted probe scenes and read the pixels (black-box probing),
(b) inspect the reference binary (strings/objdump), and (c) iterate against the provided sample.

Then satisfy:

```
/app/pov/tracer scene.pov out.ppm
```

## Success criteria

- Byte-exact (<=0.5% bytes differ) against the reference on all verifier-held scenes.
- The remaining scenes include edge positions, overlaps, off-screen spheres.
- `/app/pov/tracer.c` exists.
- Bonus: render a 160x120 scene with 40 spheres in under 5 s (`/usr/bin/time`).

## Hints

- The sample suggests the reference's mapping. The black-box approach is intended:
  probe by rendering single spheres at known centers and measuring the diameters in pixels.
- `render_ref` is unstripped; there are symbol/signature clues. The focal constant and the
  exact circle rule live there. You can also focus on the sample: it was made with this exact binary.
- There is no scene depth: only the provided fields exist.