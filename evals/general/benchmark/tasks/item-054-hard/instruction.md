# Item-054 (hard) — Reproduce a reference renderer with an undocumented
# shading model, against adversarial documentation

A legacy renderer lives in `/app/pov/`:

- `README.md` — describes the scene format and the CLI, but its technical notes
  are **partially wrong on purpose** (they were written by a different team and
  contradict what the binary actually does).
- `render_ref` — the authoritative precompiled renderer.
- `scene0.pov`, `scene0.ppm` — one real input/output pair from `render_ref`.
- `check.py` — PPM comparator (prints % of differing bytes).

Scene format (see README):
```
size <W> <H>
background <r> <g> <b>
sphere <x> <y> <radius> <r> <g> <b>
```

Your job: write `/app/pov/tracer.c`, compile it to `/app/pov/tracer`, so that it
reproduces `render_ref` byte-for-byte on **every** valid scene, including hidden
verifier scenes with adversarial edge cases. You have four investigation routes:

1. **Visual evidence** — study `scene0.ppm` closely (e.g. with a tiny python
   pixel dump). The sample is ground truth: any claim in README that contradicts
   what the sample pixels show is the adversarial doc lie.
2. **Black-box probing** — render crafted scenes with `render_ref` (single
   sphere at the center, known world radius) and read the output pixels. Measure
   the radial intensity profile of one sphere exactly; that determines the
   shading law and lets you recover its parameters quantitatively.
3. **Static binary analysis** — `render_ref` is unstripped; `strings` and
   `objdump` are installed. Numeric constants live in the data/rodata section.
4. **Differential iteration** — run `check.py` between your `tracer` and
   `render_ref` on your own probe scenes until the difference is 0.000%.

Contract (both binaries):
```
/app/pov/tracer scene.pov out.ppm
```

## Success criteria

- ≤0.5% differing bytes vs the reference on all hidden scenes (which include a
  zero-radius sphere, tiny radii, off-screen spheres, heavy overlap).
- `/app/pov/tracer.c` exists and your binary renders a 160x120 scene with 40
  spheres in under 5 seconds.

## Notes

- The README's "no shading, every pixel gets exactly the sphere's color" is
  false. Verify against the sample before believing it.
- The camera focal length and the shading law are both recoverable from probes;
  the shading law has exactly two free parameters (intercept and slope of a
  linear radial falloff). Match them to <0.002 to pass the hidden scenes.