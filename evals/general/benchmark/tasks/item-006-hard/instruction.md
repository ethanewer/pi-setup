In `/app/pov2/` there is a legacy renderer from the POV-Ray-2.2 era. It reads a POV-style scene (`scene.pov`), renders flat-shaded spheres to a binary P6 PPM, and writes `out.ppm`. It has **two independent classes of defects**: (1) the pre-ANSI C++ source no longer compiles on a modern C++ compiler; (2) once it compiles, the rendered image is wrong — the spheres have the wrong apparent size (a numerical defect in the renderer itself).

Layout:

```
/app/pov2/
  configure        legacy build-script (emits Makefile from Makefile.in)
  Makefile.in
  render.cpp       renderer source (legacy style - does not compile; also buggy)
  scene.pov        input scene - IMMUTABLE, never modify it
  validate.py      rendered-artifact checker - DO NOT MODIFY
  README.md
```

Work sequence:

1. **Fix the legacy C++ language issues** so `render.cpp` compiles with the installed modern C++ compiler (e.g. functions invoked without prior declarations, ancient pre-ANSI function-definition syntax, a missing standard header). Patch minimally; do not change the scene format or the rendering algorithm's intent.

2. **Build** with the legacy autoconf-style flow:

   ```
   cd /app/pov2
   ./configure
   make
   ```

3. **Render and validate iteratively.** Run:

   ```
   ./render
   python3 validate.py
   ```

   `validate.py` rebuilds the expected image independently from `scene.pov` and compares it pixel-by-pixel with `out.ppm`, reporting ``PERFECT MATCH` or a mismatch count. Even after the code compiles, you will almost certainly see a large mismatch — that is the rendering defect. Diagnose the faulty sphere math (what makes the displayed sphere size wrong for every pixel) and patch it minimally. Keep re-rendering and re-validating until `python3 validate.py` prints `PERFECT MATCH`.

Constraints:

- Never modify `scene.pov` or `validate.py` (immutable inputs — the grader verifies them unchanged).
- Do not install additional packages (compiler and python3 already present).
- Final state: `./configure && make` builds `render`, `./render` produces `/app/pov2/out.ppm`, and `python3 validate.py` reports `PERFECT MATCH`.